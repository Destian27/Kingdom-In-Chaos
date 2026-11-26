#include <jni.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>

#ifndef RTLD_NOLOAD
#define RTLD_NOLOAD 0x00004
#endif

namespace {
using GetLevelManager = void* (*)();
using GetIntValue = int (*)(void*);
using AdjustWithSourceAndFlag = void (*)(int, int, bool);
using AdjustWithSource = void (*)(int, int);
using AdjustWithFlag = void (*)(int, bool);
using AdjustSimple = void (*)(int);
using GetUserDataManager = void* (*)();
using GetGlobalInfo = int (*)(void*, int);
using SetGlobalInfo = void (*)(void*, int, int);

jstring result(JNIEnv* env, const char* value) {
    return env->NewStringUTF(value ? value : "UNKNOWN_ERROR");
}

void* symbol(void* handle, const char* name) {
    return handle ? dlsym(handle, name) : nullptr;
}

bool reconcile(int current, int target,
               AdjustWithSourceAndFlag increase,
               AdjustWithSource decrease) {
    if (current == target) return true;
    if (target > current) {
        if (!increase) return false;
        // Pass enum ordinal 0; stripped binary strings do not reveal the source label.
        increase(target - current, 0, true);
    } else {
        if (!decrease) return false;
        decrease(current - target, 0);
    }
    return true;
}

bool reconcileGoblin(int current, int target,
                     AdjustWithFlag increase,
                     AdjustSimple decrease) {
    if (current == target) return true;
    if (target > current) {
        if (!increase) return false;
        increase(target - current, true);
    } else {
        if (!decrease) return false;
        decrease(current - target);
    }
    return true;
}
} // namespace

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

    // libgame.so must already be loaded by the Cocos2d-x GameActivity.
    void* game = dlopen("libgame.so", RTLD_NOW | RTLD_NOLOAD);
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
    AdjustWithFlag increaseGoblin = targetGoblinCoins >= 0
            ? reinterpret_cast<AdjustWithFlag>(symbol(game, "_Z18IncreaseGoblinCoinib")) : nullptr;
    AdjustSimple decreaseGoblin = targetGoblinCoins >= 0
            ? reinterpret_cast<AdjustSimple>(symbol(game, "_Z18DecreaseGoblinCoini")) : nullptr;

    // Original FestivalActivityScorePoint helpers use UserDataType 0x85.
    // The original label updater also reads this exact key, so it is the
    // native Halloween/event eye currency shown by the screenshot.
    GetUserDataManager getUserDataManager = targetEventEyes >= 0
            ? reinterpret_cast<GetUserDataManager>(symbol(game, "_ZN15UserDataManager11getInstanceEv")) : nullptr;
    GetGlobalInfo getGlobalInfo = targetEventEyes >= 0
            ? reinterpret_cast<GetGlobalInfo>(symbol(game, "_ZN15UserDataManager13getGlobalInfoE12UserDataType")) : nullptr;
    SetGlobalInfo setGlobalInfo = targetEventEyes >= 0
            ? reinterpret_cast<SetGlobalInfo>(symbol(game, "_ZN15UserDataManager13setGlobalInfoE12UserDataTypei")) : nullptr;

    if ((needLevelManager && !getManager) ||
        (targetCoins >= 0 && (!getCoins || !increaseCoins || !decreaseCoins)) ||
        (targetCrystals >= 0 && (!getCrystals || !increaseCrystals || !decreaseCrystals)) ||
        (targetGoblinCoins >= 0 && (!getGoblinCoins || !increaseGoblin || !decreaseGoblin)) ||
        (targetEventEyes >= 0 && (!getUserDataManager || !getGlobalInfo || !setGlobalInfo))) {
        dlclose(game);
        return result(env, "GAME_SYMBOL_MISSING|unsupported_libgame_build");
    }

    void* manager = needLevelManager ? getManager() : nullptr;
    if (needLevelManager && !manager) {
        dlclose(game);
        return result(env, "GAME_STATE_NOT_READY");
    }

    const int beforeCoins = targetCoins >= 0 ? getCoins(manager) : -1;
    const int beforeCrystals = targetCrystals >= 0 ? getCrystals(manager) : -1;
    const int beforeGoblin = targetGoblinCoins >= 0 ? getGoblinCoins(manager) : -1;
    void* userDataManager = targetEventEyes >= 0 ? getUserDataManager() : nullptr;
    if (targetEventEyes >= 0 && !userDataManager) {
        dlclose(game);
        return result(env, "USER_DATA_MANAGER_NOT_READY");
    }
    const int beforeEventEyes = targetEventEyes >= 0 ? getGlobalInfo(userDataManager, 0x85) : -1;
    if ((targetCoins >= 0 && beforeCoins < 0) ||
        (targetCrystals >= 0 && beforeCrystals < 0) ||
        (targetGoblinCoins >= 0 && beforeGoblin < 0) ||
        (targetEventEyes >= 0 && beforeEventEyes < 0)) {
        dlclose(game);
        return result(env, "INVALID_NATIVE_BALANCE");
    }

    const int wantedCoins = static_cast<int>(targetCoins);
    const int wantedCrystals = static_cast<int>(targetCrystals);
    const int wantedGoblin = static_cast<int>(targetGoblinCoins);
    const int wantedEventEyes = static_cast<int>(targetEventEyes);

    const bool coinsOk = targetCoins < 0 || reconcile(beforeCoins, wantedCoins, increaseCoins, decreaseCoins);
    const bool crystalsOk = targetCrystals < 0 || reconcile(beforeCrystals, wantedCrystals, increaseCrystals, decreaseCrystals);
    const bool goblinOk = targetGoblinCoins < 0 || reconcileGoblin(beforeGoblin, wantedGoblin, increaseGoblin, decreaseGoblin);
    if (targetEventEyes >= 0 && beforeEventEyes != wantedEventEyes) {
        // Same UserDataType and setter used by Increase/DecreaseFestivalActivityScorePoint.
        setGlobalInfo(userDataManager, 0x85, wantedEventEyes);
    }

    const int afterCoins = targetCoins >= 0 ? getCoins(manager) : -1;
    const int afterCrystals = targetCrystals >= 0 ? getCrystals(manager) : -1;
    const int afterGoblin = targetGoblinCoins >= 0 ? getGoblinCoins(manager) : -1;
    const int afterEventEyes = targetEventEyes >= 0 ? getGlobalInfo(userDataManager, 0x85) : -1;
    dlclose(game);

    const bool verified = coinsOk && crystalsOk && goblinOk &&
            (targetCoins < 0 || afterCoins == wantedCoins) &&
            (targetCrystals < 0 || afterCrystals == wantedCrystals) &&
            (targetGoblinCoins < 0 || afterGoblin == wantedGoblin) &&
            (targetEventEyes < 0 || afterEventEyes == wantedEventEyes);
    char message[240];
    snprintf(message, sizeof(message), "%s|coins=%d/%d|crystals=%d/%d|goblin=%d/%d|event_eyes=%d/%d",
             verified ? "OK" : "APPLY_MISMATCH",
             afterCoins, wantedCoins, afterCrystals, wantedCrystals, afterGoblin, wantedGoblin,
             afterEventEyes, wantedEventEyes);
    return result(env, message);
}
