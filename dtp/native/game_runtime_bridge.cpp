#include <jni.h>
#include <dlfcn.h>
#include <limits.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef RTLD_NOLOAD
#define RTLD_NOLOAD 0x00004
#endif

namespace {
using GetLevelManager = void* (*)();
using GetIntValue = int (*)(void*);
using AdjustWithSourceAndFlag = void (*)(int, int, bool);
using AdjustWithSource = bool (*)(int, int);
using GetUserDataManager = void* (*)();
using IsSwitchOn = bool (*)(void*, int);
using OnPaidOK = void (*)(void*, int);
using GetPriceManager = void* (*)();
using IncreaseCurrency = void (*)(int, int, bool);
using IncreaseCrystal = void (*)(int, int, bool);
using IncreaseLife = void (*)(int, bool);
using BalanceLifeStatus = void (*)(int*, int*);
using GetLifeMax = int (*)();

JavaVM* g_vm = nullptr;
jclass g_bridgeClass = nullptr;
jmethodID g_onCrystalsEarned = nullptr;
jmethodID g_onBarterResult = nullptr;

OnPaidOK g_onPaidOK = nullptr;
GetPriceManager g_getPriceManager = nullptr;
GetUserDataManager g_getUserDataManager = nullptr;
IsSwitchOn g_isSwitchOn = nullptr;
AdjustWithSource g_decreaseCoins = nullptr;
AdjustWithSource g_decreaseCrystals = nullptr;
IncreaseCurrency g_increaseCoins = nullptr;
IncreaseCrystal g_increaseCrystals = nullptr;
IncreaseCrystal g_originalIncreaseCrystals = nullptr;
void* g_increaseCrystalTrampoline = nullptr;
void* g_gameHandle = nullptr;
bool g_hooksInstalled = false;
bool g_crystalHookInstalled = false;

jstring result(JNIEnv* env, const char* value) {
    return env->NewStringUTF(value ? value : "UNKNOWN_ERROR");
}

void* symbol(void* handle, const char* name) {
    return handle ? dlsym(handle, name) : nullptr;
}

// v17.14.6: pelindung SIGSEGV untuk membaca saldo dari libgame.so.
// LevelManager::getInstance() sudah mengembalikan pointer saat GameActivity baru dibuat,
// tetapi data di dalamnya (DHInt) belum dimuat. LevelManager::getCoin() lalu membaca
// anggota dari pointer NULL (fault addr 0x18, DHValue::getValue) dan mematikan proses.
// Pembacaan dibungkus sigsetjmp/siglongjmp: jika game belum siap, fungsi native
// mengembalikan GAME_STATE_NOT_READY dan game tetap hidup. Fault di luar blok terlindung
// diteruskan ke handler sebelumnya (perilaku crash normal tidak berubah).
__thread sigjmp_buf* t_guardJump = nullptr;
struct sigaction g_guardPrevious;
volatile int g_guardInstalled = 0;

void guardSegvHandler(int sig, siginfo_t* info, void* context) {
    if (t_guardJump) siglongjmp(*t_guardJump, 1);
    if (g_guardPrevious.sa_flags & SA_SIGINFO) {
        if (g_guardPrevious.sa_sigaction) {
            g_guardPrevious.sa_sigaction(sig, info, context);
            return;
        }
    } else if (g_guardPrevious.sa_handler != SIG_DFL && g_guardPrevious.sa_handler != SIG_IGN) {
        g_guardPrevious.sa_handler(sig);
        return;
    }
    // Tidak ada handler lain: kembalikan ke default agar fault diulang dan crash apa adanya.
    signal(sig, SIG_DFL);
}

void installGuardHandler() {
    if (g_guardInstalled) return;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = guardSegvHandler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    if (sigaction(SIGSEGV, &action, &g_guardPrevious) == 0) g_guardInstalled = 1;
}

// Menjalankan body(arg); mengembalikan false bila body menyebabkan SIGSEGV.
bool runGuarded(void (*body)(void*), void* arg) {
    installGuardHandler();
    if (!g_guardInstalled) {
        body(arg);  // handler tidak dapat dipasang: perilaku lama
        return true;
    }
    sigjmp_buf jump;
    sigjmp_buf* volatile previous = t_guardJump;
    if (sigsetjmp(jump, 1) == 0) {
        t_guardJump = &jump;
        body(arg);
        t_guardJump = previous;
        return true;
    }
    t_guardJump = previous;
    return false;
}

struct WalletRead {
    void* manager;
    GetIntValue getCoins;
    GetIntValue getCrystals;
    GetIntValue getGoblin;
    BalanceLifeStatus balanceLife;
    GetLifeMax getLifeMax;
    int coins;
    int crystals;
    int goblin;
    int life;
    int secondsToNextLife;
    int lifeMax;
};

void readWalletBody(void* raw) {
    WalletRead* w = static_cast<WalletRead*>(raw);
    w->coins = w->getCoins(w->manager);
    w->crystals = w->getCrystals(w->manager);
    w->goblin = w->getGoblin(w->manager);
    w->life = 0;
    w->secondsToNextLife = 0;
    w->balanceLife(&w->life, &w->secondsToNextLife);
    w->lifeMax = w->getLifeMax();
}

// false = game belum siap (SIGSEGV ditangkap); saldo tidak boleh dipakai.
bool readWalletGuarded(WalletRead* w) {
    return runGuarded(readWalletBody, w);
}

struct EconomyRead {
    void* manager;
    GetIntValue getCoins;
    GetIntValue getCrystals;
    GetIntValue getGoblin;
    int coins;
    int crystals;
    int goblin;
};

void readEconomyBody(void* raw) {
    EconomyRead* e = static_cast<EconomyRead*>(raw);
    e->coins = e->getCoins ? e->getCoins(e->manager) : -1;
    e->crystals = e->getCrystals ? e->getCrystals(e->manager) : -1;
    e->goblin = e->getGoblin ? e->getGoblin(e->manager) : -1;
}

bool protectCode(void* address, size_t length, int protection) {
    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) return false;
    uintptr_t start = reinterpret_cast<uintptr_t>(address);
    uintptr_t page = start & ~static_cast<uintptr_t>(pageSize - 1);
    uintptr_t end = (start + length + static_cast<uintptr_t>(pageSize - 1)) &
            ~static_cast<uintptr_t>(pageSize - 1);
    return mprotect(reinterpret_cast<void*>(page), end - page, protection) == 0;
}

void makeThumbJump(uint8_t* out, void* destination) {
    // Thumb-2: ldr.w pc, [pc, #0]; .word destination|1
    out[0] = 0xDF; out[1] = 0xF8; out[2] = 0x00; out[3] = 0xF0;
    uint32_t target = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(destination)) | 1U;
    memcpy(out + 4, &target, sizeof(target));
}

bool patchThumbJump(void* targetFunction, void* hookFunction) {
    if (!targetFunction || !hookFunction) return false;
    uint8_t* code = reinterpret_cast<uint8_t*>(reinterpret_cast<uintptr_t>(targetFunction) & ~1U);
    uint8_t patch[8];
    makeThumbJump(patch, hookFunction);
    if (!protectCode(code, sizeof(patch), PROT_READ | PROT_WRITE | PROT_EXEC)) return false;
    memcpy(code, patch, sizeof(patch));
    __builtin___clear_cache(reinterpret_cast<char*>(code), reinterpret_cast<char*>(code + sizeof(patch)));
    protectCode(code, sizeof(patch), PROT_READ | PROT_EXEC);
    return true;
}

void* makeThumbTrampoline(void* targetFunction, size_t overwrittenBytes) {
    if (!targetFunction || overwrittenBytes != 8) return nullptr;
    void* memory = mmap(nullptr, 16, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (memory == MAP_FAILED) return nullptr;
    uint8_t* trampoline = static_cast<uint8_t*>(memory);
    uint8_t* original = reinterpret_cast<uint8_t*>(reinterpret_cast<uintptr_t>(targetFunction) & ~1U);
    memcpy(trampoline, original, overwrittenBytes);
    uint8_t jump[8];
    void* resume = reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(original + overwrittenBytes) | 1U);
    makeThumbJump(jump, resume);
    memcpy(trampoline + overwrittenBytes, jump, sizeof(jump));
    if (mprotect(memory, 16, PROT_READ | PROT_EXEC) != 0) {
        munmap(memory, 16);
        return nullptr;
    }
    __builtin___clear_cache(reinterpret_cast<char*>(trampoline), reinterpret_cast<char*>(trampoline + 16));
    return reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(memory) | 1U);
}

JNIEnv* currentEnv(bool* attached) {
    if (attached) *attached = false;
    if (!g_vm) return nullptr;
    JNIEnv* env = nullptr;
    if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return env;
#if defined(__ANDROID__)
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return nullptr;
#else
    if (g_vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) != JNI_OK) return nullptr;
#endif
    if (attached) *attached = true;
    return env;
}

void notifyBarter(int offerId, int status) {
    if (!g_vm || !g_bridgeClass || !g_onBarterResult) return;
    bool attached = false;
    JNIEnv* env = currentEnv(&attached);
    if (!env) return;
    env->CallStaticVoidMethod(g_bridgeClass, g_onBarterResult, offerId, status);
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (attached) g_vm->DetachCurrentThread();
}

void notifyCrystalsEarned(int amount) {
    if (amount <= 0 || !g_vm || !g_bridgeClass || !g_onCrystalsEarned) return;
    bool attached = false;
    JNIEnv* env = currentEnv(&attached);
    if (!env) return;
    env->CallStaticVoidMethod(g_bridgeClass, g_onCrystalsEarned, amount);
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (attached) g_vm->DetachCurrentThread();
}

// Replaces the native IncreaseCrystal entry while retaining its original behavior.
void dtpIncreaseCrystalHook(int amount, int source, bool playSound) {
    if (g_originalIncreaseCrystals) {
        g_originalIncreaseCrystals(amount, source, playSound);
    }
    // Count newly earned DM only; spending DM never reduces this lifetime total.
    notifyCrystalsEarned(amount);
}

struct OfferCost {
    bool usesCoins;
    int amount;
};

int doCurrencyExchange(int offerId);

bool getOfferCost(int paymentId, OfferCost* out) {
    if (!out) return false;
    if (paymentId == 0) { *out = {false, 299}; return true; }       // Newbie Value Pack
    if (paymentId == 1) { *out = {false, 999}; return true; }       // Newbie Rich Pack
    if (paymentId >= 26 && paymentId <= 37) {                       // Hero offers
        static const int heroCosts[6] = {140, 350, 1400, 490, 490, 700};
        *out = {false, heroCosts[(paymentId - 26) % 6]};
        return true;
    }
    if (paymentId == 38) { *out = {false, 599}; return true; }      // Weekly pack
    if (paymentId == 39) { *out = {false, 99}; return true; }       // PvP ticket
    if (paymentId == 40) { *out = {true, 30000}; return true; }     // 30-day VIP
    if (paymentId >= 41 && paymentId <= 48) { *out = {false, 499}; return true; } // Equipment ($4.99 equivalent)
    if (paymentId == 49) { *out = {true, 3500}; return true; }      // Luck Spree ($1 coin equivalent)
    if (paymentId == 50) { *out = {false, 560}; return true; }      // Hero bundle
    if (paymentId == 51) { *out = {false, 420}; return true; }      // Gear bundle
    if (paymentId == 52) { *out = {false, 499}; return true; }      // Seasonal offer
    if (paymentId == 53) { *out = {false, 1499}; return true; }     // Seasonal offer
    return false;
}

int purchaseOffer(void* priceManager, int paymentId) {
    if (!priceManager && g_getPriceManager) priceManager = g_getPriceManager();
    if (!priceManager || !g_onPaidOK || !g_decreaseCoins || !g_decreaseCrystals) return 5;

    // Former cash-priced currency packs now route directly to a matching
    // currency exchange. They never call onPaidOK() or the billing provider.
    if (paymentId >= 2 && paymentId <= 13) {
        return doCurrencyExchange((paymentId - 2) % 3);
    }
    if (paymentId >= 14 && paymentId <= 25) {
        return doCurrencyExchange(3 + ((paymentId - 14) % 3));
    }

    OfferCost cost{};
    if (!getOfferCost(paymentId, &cost)) return 4;

    // Luck Spree is a one-time gift in the original game. Respect its native flag.
    if (paymentId == 49 && g_getUserDataManager && g_isSwitchOn) {
        void* data = g_getUserDataManager();
        if (data && g_isSwitchOn(data, 0x31)) return 3;
    }

    // DataSourcesType 6 is the game's existing shop-purchase source.
    const bool paid = cost.usesCoins
            ? g_decreaseCoins(cost.amount, 6)
            : g_decreaseCrystals(cost.amount, 6);
    if (!paid) return cost.usesCoins ? 1 : 2;

    // Keep the original reward implementation: VIP duration, rookie packs,
    // hero unlocks, equipment and all bundled items are granted by libgame.so.
    g_onPaidOK(priceManager, paymentId);
    return 0;
}

void dtpPricePayHook(void* self, int paymentId) {
    const int status = purchaseOffer(self, paymentId);
    notifyBarter(paymentId, status);
}

int doCurrencyExchange(int offerId) {
    if (!g_decreaseCoins || !g_decreaseCrystals || !g_increaseCoins || !g_increaseCrystals) return 5;
    int cost = 0;
    int reward = 0;
    bool payWithCoins = false;
    bool rewardCoins = false;
    switch (offerId) {
        case 0: cost = 200; reward = 10000; payWithCoins = false; rewardCoins = true; break;
        case 1: cost = 700; reward = 35000; payWithCoins = false; rewardCoins = true; break;
        case 2: cost = 2400; reward = 120000; payWithCoins = false; rewardCoins = true; break;
        case 3: cost = 10000; reward = 200; payWithCoins = true; rewardCoins = false; break;
        case 4: cost = 35000; reward = 700; payWithCoins = true; rewardCoins = false; break;
        case 5: cost = 120000; reward = 2400; payWithCoins = true; rewardCoins = false; break;
        default: return -1;
    }
    const bool deducted = payWithCoins
            ? g_decreaseCoins(cost, 6)
            : g_decreaseCrystals(cost, 6);
    if (!deducted) return payWithCoins ? 1 : 2;
    if (rewardCoins) g_increaseCoins(reward, 6, true);
    else g_increaseCrystals(reward, 6, true);
    return 0;
}

void* loadGameLibrary() {
    if (g_gameHandle) return g_gameHandle;
    g_gameHandle = dlopen("libgame.so", RTLD_NOW | RTLD_NOLOAD);
    return g_gameHandle;
}

} // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass local = env->FindClass("com/destian/dtp/NativeGameRuntimeBridge");
    if (!local) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        return JNI_VERSION_1_6;
    }
    g_bridgeClass = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    if (g_bridgeClass) {
        g_onCrystalsEarned = env->GetStaticMethodID(g_bridgeClass, "onCrystalsEarned", "(I)V");
        if (env->ExceptionCheck()) env->ExceptionClear();
        g_onBarterResult = env->GetStaticMethodID(g_bridgeClass, "onBarterResult", "(II)V");
        if (env->ExceptionCheck()) env->ExceptionClear();
    }
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_destian_dtp_NativeGameRuntimeBridge_applyEconomyNative(
        JNIEnv* env, jclass, jlong targetCoins, jlong targetCrystals, jlong targetGoblinCoins,
        jlong targetEventEyes) {
    if (targetCoins < -1 || targetCoins > INT_MAX ||
        targetCrystals < -1 || targetCrystals > INT_MAX ||
        targetGoblinCoins < -1 || targetGoblinCoins > INT_MAX ||
        targetEventEyes < -1 || targetEventEyes > INT_MAX ||
        (targetCoins < 0 && targetCrystals < 0 && targetGoblinCoins < 0 && targetEventEyes < 0)) {
        return result(env, "UNSUPPORTED_RANGE|native_int_balance_required");
    }
    void* game = loadGameLibrary();
    if (!game) return result(env, "GAME_LIBRARY_NOT_LOADED");

    const bool needLevelManager = targetCoins >= 0 || targetCrystals >= 0 || targetGoblinCoins >= 0;
    GetLevelManager getManager = needLevelManager
            ? reinterpret_cast<GetLevelManager>(symbol(game, "_ZN12LevelManager11getInstanceEv")) : nullptr;
    GetIntValue getCoins = targetCoins >= 0
            ? reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager7getCoinEv")) : nullptr;
    GetIntValue getCrystals = targetCrystals >= 0
            ? reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager10getCrystalEv")) : nullptr;
    GetIntValue getGoblinCoins = targetGoblinCoins >= 0
            ? reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager13getGoblinCoinEv")) : nullptr;
    AdjustWithSourceAndFlag increaseCoins = targetCoins >= 0
            ? reinterpret_cast<AdjustWithSourceAndFlag>(symbol(game, "_Z12IncreaseCoini15DataSourcesTypeb")) : nullptr;
    AdjustWithSource decreaseCoins = targetCoins >= 0
            ? reinterpret_cast<AdjustWithSource>(symbol(game, "_Z12DecreaseCoini15DataSourcesType")) : nullptr;
    AdjustWithSourceAndFlag increaseCrystals = targetCrystals >= 0
            ? reinterpret_cast<AdjustWithSourceAndFlag>(symbol(game, "_Z15IncreaseCrystali15DataSourcesTypeb")) : nullptr;
    AdjustWithSource decreaseCrystals = targetCrystals >= 0
            ? reinterpret_cast<AdjustWithSource>(symbol(game, "_Z15DecreaseCrystali15DataSourcesType")) : nullptr;
    using AdjustWithFlag = void (*)(int, bool);
    using AdjustSimple = void (*)(int);
    AdjustWithFlag increaseGoblin = targetGoblinCoins >= 0
            ? reinterpret_cast<AdjustWithFlag>(symbol(game, "_Z18IncreaseGoblinCoinib")) : nullptr;
    AdjustSimple decreaseGoblin = targetGoblinCoins >= 0
            ? reinterpret_cast<AdjustSimple>(symbol(game, "_Z18DecreaseGoblinCoini")) : nullptr;
    GetUserDataManager getUserDataManager = targetEventEyes >= 0
            ? reinterpret_cast<GetUserDataManager>(symbol(game, "_ZN15UserDataManager11getInstanceEv")) : nullptr;
    using GetGlobalInfo = int (*)(void*, int);
    using SetGlobalInfo = void (*)(void*, int, int);
    GetGlobalInfo getGlobalInfo = targetEventEyes >= 0
            ? reinterpret_cast<GetGlobalInfo>(symbol(game, "_ZN15UserDataManager13getGlobalInfoE12UserDataType")) : nullptr;
    SetGlobalInfo setGlobalInfo = targetEventEyes >= 0
            ? reinterpret_cast<SetGlobalInfo>(symbol(game, "_ZN15UserDataManager13setGlobalInfoE12UserDataTypei")) : nullptr;

    if ((needLevelManager && !getManager) ||
        (targetCoins >= 0 && (!getCoins || !increaseCoins || !decreaseCoins)) ||
        (targetCrystals >= 0 && (!getCrystals || !increaseCrystals || !decreaseCrystals)) ||
        (targetGoblinCoins >= 0 && (!increaseGoblin || !decreaseGoblin)) ||
        (targetEventEyes >= 0 && (!getUserDataManager || !getGlobalInfo || !setGlobalInfo))) {
        return result(env, "GAME_SYMBOL_MISSING|unsupported_libgame_build");
    }
    void* manager = needLevelManager ? getManager() : nullptr;
    if (needLevelManager && !manager) return result(env, "GAME_STATE_NOT_READY");

    EconomyRead econBefore = {manager, getCoins, getCrystals, getGoblinCoins, -1, -1, -1};
    if (needLevelManager && !runGuarded(readEconomyBody, &econBefore)) {
        return result(env, "GAME_STATE_NOT_READY|economy_read_faulted");
    }
    const int beforeCoins = targetCoins >= 0 ? econBefore.coins : -1;
    const int beforeCrystals = targetCrystals >= 0 ? econBefore.crystals : -1;
    const int beforeGoblin = targetGoblinCoins >= 0 ? econBefore.goblin : -1;
    void* userDataManager = targetEventEyes >= 0 ? getUserDataManager() : nullptr;
    if (targetEventEyes >= 0 && !userDataManager) return result(env, "USER_DATA_MANAGER_NOT_READY");
    const int beforeEventEyes = targetEventEyes >= 0 ? getGlobalInfo(userDataManager, 0x85) : -1;
    if ((targetCoins >= 0 && beforeCoins < 0) || (targetCrystals >= 0 && beforeCrystals < 0) ||
        (targetGoblinCoins >= 0 && beforeGoblin < 0) || (targetEventEyes >= 0 && beforeEventEyes < 0)) {
        return result(env, "INVALID_NATIVE_BALANCE");
    }

    const int wantedCoins = static_cast<int>(targetCoins);
    const int wantedCrystals = static_cast<int>(targetCrystals);
    const int wantedGoblin = static_cast<int>(targetGoblinCoins);
    const int wantedEventEyes = static_cast<int>(targetEventEyes);
    const bool coinsOk = targetCoins < 0 || (wantedCoins >= beforeCoins
            ? (increaseCoins(wantedCoins - beforeCoins, 0, true), true)
            : decreaseCoins(beforeCoins - wantedCoins, 0));
    const bool crystalsOk = targetCrystals < 0 || (wantedCrystals >= beforeCrystals
            ? (increaseCrystals(wantedCrystals - beforeCrystals, 0, true), true)
            : decreaseCrystals(beforeCrystals - wantedCrystals, 0));
    bool goblinOk = true;
    if (targetGoblinCoins >= 0) {
        if (wantedGoblin >= beforeGoblin) increaseGoblin(wantedGoblin - beforeGoblin, true);
        else decreaseGoblin(beforeGoblin - wantedGoblin);
    }
    if (targetEventEyes >= 0 && beforeEventEyes != wantedEventEyes) {
        setGlobalInfo(userDataManager, 0x85, wantedEventEyes);
    }

    EconomyRead econAfter = {manager, getCoins, getCrystals, getGoblinCoins, -1, -1, -1};
    if (needLevelManager) runGuarded(readEconomyBody, &econAfter);
    const int afterCoins = targetCoins >= 0 ? econAfter.coins : -1;
    const int afterCrystals = targetCrystals >= 0 ? econAfter.crystals : -1;
    const int afterGoblin = targetGoblinCoins >= 0 ? econAfter.goblin : -1;
    const int afterEventEyes = targetEventEyes >= 0 ? getGlobalInfo(userDataManager, 0x85) : -1;
    const bool verified = coinsOk && crystalsOk && goblinOk &&
            (targetCoins < 0 || afterCoins == wantedCoins) &&
            (targetCrystals < 0 || afterCrystals == wantedCrystals) &&
            (targetGoblinCoins < 0 || afterGoblin == wantedGoblin) &&
            (targetEventEyes < 0 || afterEventEyes == wantedEventEyes);
    char message[240];
    snprintf(message, sizeof(message), "%s|coins=%d/%d|crystals=%d/%d|goblin=%d/%d|event_eyes=%d/%d",
             verified ? "OK" : "APPLY_MISMATCH", afterCoins, wantedCoins,
             afterCrystals, wantedCrystals, afterGoblin, wantedGoblin, afterEventEyes, wantedEventEyes);
    return result(env, message);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_destian_dtp_NativeGameRuntimeBridge_installEconomyHooksNative(JNIEnv* env, jclass) {
    if (g_hooksInstalled) return result(env, "OK|hooks_already_installed");
    if (!g_onCrystalsEarned || !g_onBarterResult || !g_bridgeClass) {
        return result(env, "BRIDGE_CALLBACK_UNAVAILABLE");
    }
    void* game = loadGameLibrary();
    if (!game) return result(env, "GAME_LIBRARY_NOT_LOADED");

    void* pay = symbol(game, "_ZN12PriceManager3payEi");
    g_onPaidOK = reinterpret_cast<OnPaidOK>(symbol(game, "_ZN12PriceManager8onPaidOKEi"));
    g_getPriceManager = reinterpret_cast<GetPriceManager>(symbol(game, "_ZN12PriceManager11getInstanceEv"));
    g_getUserDataManager = reinterpret_cast<GetUserDataManager>(symbol(game, "_ZN15UserDataManager11getInstanceEv"));
    g_isSwitchOn = reinterpret_cast<IsSwitchOn>(symbol(game, "_ZN15UserDataManager10isSwitchOnE12UserDataType"));
    g_decreaseCoins = reinterpret_cast<AdjustWithSource>(symbol(game, "_Z12DecreaseCoini15DataSourcesType"));
    g_decreaseCrystals = reinterpret_cast<AdjustWithSource>(symbol(game, "_Z15DecreaseCrystali15DataSourcesType"));
    g_increaseCoins = reinterpret_cast<IncreaseCurrency>(symbol(game, "_Z12IncreaseCoini15DataSourcesTypeb"));
    g_increaseCrystals = reinterpret_cast<IncreaseCrystal>(symbol(game, "_Z15IncreaseCrystali15DataSourcesTypeb"));
    if (!pay || !g_onPaidOK || !g_getPriceManager || !g_decreaseCoins || !g_decreaseCrystals ||
        !g_increaseCoins || !g_increaseCrystals || !g_getUserDataManager || !g_isSwitchOn) {
        return result(env, "GAME_SYMBOL_MISSING|barter_hooks_not_installed");
    }

    void* crystalEntry = symbol(game, "_Z15IncreaseCrystali15DataSourcesTypeb");
    if (!g_crystalHookInstalled) {
        g_increaseCrystalTrampoline = makeThumbTrampoline(crystalEntry, 8);
        if (!g_increaseCrystalTrampoline) return result(env, "CRYSTAL_TRAMPOLINE_FAILED");
        g_originalIncreaseCrystals = reinterpret_cast<IncreaseCrystal>(g_increaseCrystalTrampoline);
        if (!patchThumbJump(crystalEntry, reinterpret_cast<void*>(&dtpIncreaseCrystalHook))) {
            return result(env, "CRYSTAL_HOOK_FAILED");
        }
        g_crystalHookInstalled = true;
    }
    if (!patchThumbJump(pay, reinterpret_cast<void*>(&dtpPricePayHook))) {
        return result(env, "PRICE_HOOK_FAILED|real_money_path_remains_blocked");
    }
    g_hooksInstalled = true;
    return result(env, "OK|native_barter_and_dm_progress_active");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_destian_dtp_NativeGameRuntimeBridge_performBarterNative(JNIEnv* env, jclass, jint offerId) {
    if (!g_hooksInstalled) return result(env, "HOOKS_NOT_READY");
    int status = 4;
    if (offerId >= 0 && offerId <= 5) {
        status = doCurrencyExchange(offerId);
    } else {
        // Overlay offer IDs 6+ map to the original in-game product/reward IDs.
        int paymentId = -1;
        if (offerId == 6) paymentId = 40;       // VIP 30 days
        else if (offerId == 7) paymentId = 49;  // Luck Spree
        else if (offerId == 8) paymentId = 0;   // Newbie Value
        else if (offerId == 9) paymentId = 1;   // Newbie Rich
        else if (offerId >= 10 && offerId <= 17) paymentId = 41 + (offerId - 10);
        else if (offerId == 18) paymentId = 50; // Hero pack
        else if (offerId == 19) paymentId = 51; // Gear pack
        else if (offerId == 20) paymentId = 38; // Weekly pack
        else if (offerId == 21) paymentId = 39; // PvP ticket
        else if (offerId == 22) paymentId = 52;
        else if (offerId == 23) paymentId = 53;
        if (paymentId >= 0) status = purchaseOffer(g_getPriceManager(), paymentId);
    }
    switch (status) {
        case 0: return result(env, "OK|barter_complete");
        case 1: return result(env, "INSUFFICIENT_COINS");
        case 2: return result(env, "INSUFFICIENT_DM");
        case 3: return result(env, "ALREADY_CLAIMED");
        case 5: return result(env, "NATIVE_NOT_READY");
        default: return result(env, "OFFER_UNAVAILABLE");
    }
}


extern "C" JNIEXPORT jstring JNICALL
Java_com_destian_dtp_NativeGameRuntimeBridge_applyWalletTargetsNative(
        JNIEnv* env, jclass, jint targetCoins, jint targetCrystals,
        jint targetGoblinCoins, jint targetLife) {
    if (targetCoins < 0 || targetCrystals < 0 || targetGoblinCoins < 0 ||
        targetLife < 0 || targetCoins > INT_MAX || targetCrystals > INT_MAX ||
        targetGoblinCoins > INT_MAX || targetLife > 24) {
        return result(env, "UNSUPPORTED_RANGE|invalid_mail_wallet_target");
    }
    void* game = loadGameLibrary();
    if (!game) return result(env, "GAME_LIBRARY_NOT_LOADED");

    GetLevelManager getManager = reinterpret_cast<GetLevelManager>(symbol(game, "_ZN12LevelManager11getInstanceEv"));
    GetIntValue getCoins = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager7getCoinEv"));
    GetIntValue getCrystals = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager10getCrystalEv"));
    GetIntValue getGoblin = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager13getGoblinCoinEv"));
    AdjustWithSourceAndFlag increaseCoins = reinterpret_cast<AdjustWithSourceAndFlag>(symbol(game, "_Z12IncreaseCoini15DataSourcesTypeb"));
    AdjustWithSourceAndFlag increaseCrystals = reinterpret_cast<AdjustWithSourceAndFlag>(symbol(game, "_Z15IncreaseCrystali15DataSourcesTypeb"));
    using IncreaseGoblin = void (*)(int, bool);
    IncreaseGoblin increaseGoblin = reinterpret_cast<IncreaseGoblin>(symbol(game, "_Z18IncreaseGoblinCoinib"));
    IncreaseLife increaseLife = reinterpret_cast<IncreaseLife>(symbol(game, "_Z12IncreaseLifeib"));
    BalanceLifeStatus balanceLife = reinterpret_cast<BalanceLifeStatus>(symbol(game, "_Z17BalanceLifeStatusPiS_"));
    GetLifeMax getLifeMax = reinterpret_cast<GetLifeMax>(symbol(game, "_Z7LifeMaxv"));

    if (!getManager || !getCoins || !getCrystals || !getGoblin || !increaseCoins ||
        !increaseCrystals || !increaseGoblin || !increaseLife || !balanceLife || !getLifeMax) {
        return result(env, "GAME_SYMBOL_MISSING|mail_reward_bridge_unavailable");
    }
    void* manager = getManager();
    if (!manager) return result(env, "GAME_STATE_NOT_READY");

    WalletRead before = {manager, getCoins, getCrystals, getGoblin, balanceLife, getLifeMax,
                         0, 0, 0, 0, 0, 0};
    if (!readWalletGuarded(&before)) return result(env, "GAME_STATE_NOT_READY|wallet_read_faulted");
    const int beforeCoins = before.coins;
    const int beforeCrystals = before.crystals;
    const int beforeGoblin = before.goblin;
    const int beforeLife = before.life;
    const int lifeMax = before.lifeMax;
    if (beforeCoins < 0 || beforeCrystals < 0 || beforeGoblin < 0 ||
        beforeLife < 0 || lifeMax <= 0 || lifeMax > 24) {
        return result(env, "INVALID_NATIVE_BALANCE|mail_reward");
    }

    // Targets are monotonic: a retry never deducts a balance or applies the same
    // letter twice. The Java journal stores targets before this function is called.
    if (beforeCoins < targetCoins) increaseCoins(targetCoins - beforeCoins, 0, true);
    if (beforeCrystals < targetCrystals) increaseCrystals(targetCrystals - beforeCrystals, 0, true);
    if (beforeGoblin < targetGoblinCoins) increaseGoblin(targetGoblinCoins - beforeGoblin, true);
    const int safeLifeTarget = targetLife > lifeMax ? lifeMax : targetLife;
    if (beforeLife < safeLifeTarget) increaseLife(safeLifeTarget - beforeLife, true);

    WalletRead after = {manager, getCoins, getCrystals, getGoblin, balanceLife, getLifeMax,
                        0, 0, 0, 0, 0, 0};
    if (!readWalletGuarded(&after)) return result(env, "APPLY_MISMATCH|wallet_reread_faulted");
    const int afterCoins = after.coins;
    const int afterCrystals = after.crystals;
    const int afterGoblin = after.goblin;
    const int afterLife = after.life;
    const int afterLifeMax = after.lifeMax;
    const bool ok = afterCoins >= targetCoins && afterCrystals >= targetCrystals &&
        afterGoblin >= targetGoblinCoins && afterLife >= safeLifeTarget &&
        afterLife <= afterLifeMax && afterLifeMax > 0 && afterLifeMax <= 24;
    char text[240];
    snprintf(text, sizeof(text), "%s|coins=%d|dm=%d|goblin=%d|life=%d/%d",
        ok ? "OK" : "APPLY_MISMATCH", afterCoins, afterCrystals, afterGoblin, afterLife, afterLifeMax);
    return result(env, text);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_destian_dtp_NativeGameRuntimeBridge_getWalletNative(JNIEnv* env, jclass) {
    void* game = loadGameLibrary();
    if (!game) return result(env, "GAME_LIBRARY_NOT_LOADED");
    GetLevelManager getManager = reinterpret_cast<GetLevelManager>(symbol(game, "_ZN12LevelManager11getInstanceEv"));
    GetIntValue getCoins = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager7getCoinEv"));
    GetIntValue getCrystals = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager10getCrystalEv"));
    GetIntValue getGoblin = reinterpret_cast<GetIntValue>(symbol(game, "_ZN12LevelManager13getGoblinCoinEv"));
    BalanceLifeStatus balanceLife = reinterpret_cast<BalanceLifeStatus>(symbol(game, "_Z17BalanceLifeStatusPiS_"));
    GetLifeMax getLifeMax = reinterpret_cast<GetLifeMax>(symbol(game, "_Z7LifeMaxv"));
    if (!getManager || !getCoins || !getCrystals || !getGoblin || !balanceLife || !getLifeMax)
        return result(env, "GAME_SYMBOL_MISSING");
    void* manager = getManager();
    if (!manager) return result(env, "GAME_STATE_NOT_READY");
    // v17.14.6: data LevelManager belum dimuat saat game baru dibuka -> getCoin() menyentuh
    // pointer NULL. Baca lewat pelindung SIGSEGV agar game tidak crash.
    WalletRead w = {manager, getCoins, getCrystals, getGoblin, balanceLife, getLifeMax,
                    0, 0, 0, 0, 0, 0};
    if (!readWalletGuarded(&w)) return result(env, "GAME_STATE_NOT_READY|wallet_read_faulted");
    char text[200];
    snprintf(text, sizeof(text), "coins=%d;dm=%d;goblin=%d;life=%d;life_max=%d",
             w.coins, w.crystals, w.goblin, w.life, w.lifeMax);
    return result(env, text);
}
