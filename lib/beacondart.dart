import 'dart:async';

import 'package:flutter/services.dart';

typedef MultiUseCallback = void Function(dynamic args);
typedef CloseChannelCallBack = void Function();

enum ChannelMethods {
  removePeer,
  getPeers,
  addPeer,
  onBeaconRequest,
  sendResponse,
  startBeacon,
  cancelListening,
  removePeers
}

class BeaconWalletClient {
  static const MethodChannel _channel = MethodChannel('beacondart');

  static final BeaconWalletClient _singleton = BeaconWalletClient._internal();

  static final Map<int, MultiUseCallback> callbacksById = {};

  static const int beaconCallBackId = 0;

  static int callBackId = 1;

  static bool beaconIsInit = false;

  factory BeaconWalletClient() {
    _channel.setMethodCallHandler(methodCallHandler);
    return _singleton;
  }

  BeaconWalletClient._internal();

  Future<bool> init(String appName, String publicKey, String address) async {
    await _startBeacon(<String, String>{
      'appName': appName,
      'publicKey': publicKey,
      'address': address,
    });

    // user completer to check beaconIsInit
    Completer<bool> completer = Completer();

    int usedTime = 0;
    const int maxWaitTime = 5000;
    const int waitTime = 500;

    check(int usedTime) {
      if (usedTime == maxWaitTime) {
        completer.complete(false);
      }

      if (beaconIsInit) {
        completer.complete(true);
      } else {
        usedTime += waitTime;
        Duration timeout = const Duration(milliseconds: waitTime);
        Timer(timeout, () => check(usedTime));
      }
    }

    check(usedTime);

    return completer.future;
  }

  static Future<void> methodCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'callListener':
        callbacksById[call.arguments["id"]]!(call.arguments["args"]);
        break;
      default:
    }
  }

  Future<bool> addPeer(Map<String, String> dApp) async {
    final bool status = await _channel
        .invokeMethod(ChannelMethods.addPeer.name, <String, String>{
      "id": dApp["id"]!,
      "name": dApp["name"]!,
      "publicKey": dApp["publicKey"]!,
      "relayServer": dApp["relayServer"]!,
      "version": dApp["version"]!
    });
    return status;
  }

  Future<bool> removePeer(String peerPublicKey) async {
    final bool status = await _channel.invokeMethod(
      ChannelMethods.removePeer.name,
      peerPublicKey,
    );
    return status;
  }

  Future<bool> removePeers() async {
    final bool status = await _channel.invokeMethod(
      ChannelMethods.removePeers.name,
    );
    return status;
  }

  Future<CloseChannelCallBack> getPeers(MultiUseCallback responder) async {
    CloseChannelCallBack cancel = await callBackRequest(
      ChannelMethods.getPeers.name,
      responder,
    );
    return cancel;
  }

  Future<CloseChannelCallBack> onBeaconRequest(
    MultiUseCallback responder,
  ) async {
    CloseChannelCallBack cancel = await callBackRequest(
      ChannelMethods.onBeaconRequest.name,
      responder,
    );
    return cancel;
  }

  Future<CloseChannelCallBack> sendResponse(
    Map<String, dynamic> args,
    MultiUseCallback responder,
  ) async {
    CloseChannelCallBack cancel = await callBackRequestWithArgs(
      ChannelMethods.sendResponse.name,
      responder,
      args,
    );
    return cancel;
  }

  _startBeacon(
    Map<String, String> args,
  ) async {
    CloseChannelCallBack cancel = await callBackRequestWithArgs(
      ChannelMethods.startBeacon.name,
      (response) => beaconIsInit = true,
      args,
    );
    return cancel;
  }

  Future<CloseChannelCallBack> callBackRequest(
    String callBack,
    MultiUseCallback responder,
  ) async {
    int currentListenerId = _nextCallbackId(callBack);
    callbacksById[currentListenerId] = responder;
    await _channel.invokeMethod(
      callBack,
      currentListenerId,
    );
    return () {
      _channel.invokeMethod(
        ChannelMethods.cancelListening.name,
        currentListenerId,
      );
      callbacksById.remove(currentListenerId);
    };
  }

  Future<CloseChannelCallBack> callBackRequestWithArgs(
    String callBack,
    MultiUseCallback responder,
    Map<String, dynamic> args,
  ) async {
    int currentListenerId = _nextCallbackId(callBack);
    callbacksById[currentListenerId] = responder;
    await _channel.invokeMethod(
      callBack,
      {
        "callBackId": currentListenerId,
        ...args,
      },
    );
    return () {
      _channel.invokeMethod(
        ChannelMethods.cancelListening.name,
        currentListenerId,
      );
      callbacksById.remove(currentListenerId);
    };
  }

  int _nextCallbackId(String methodName) {
    if (methodName == ChannelMethods.onBeaconRequest.name) {
      return beaconCallBackId;
    }
    return callBackId++;
  }
}
