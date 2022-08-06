import 'dart:convert';

import 'package:base_codecs/base_codecs.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:beacondart/beacondart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  BeaconWalletClient bmw = BeaconWalletClient();

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    await bmw.init(
      'Ejara',
      '9ae0875d510904b0b15d251d8def1f5f3353e9799841c0ed6d7ac718f04459a0',
      'tz1SkbBZg15BXPRkYCrSzhY6rq4tKGtpUSWv',
    );
  }

  String b58ToString(String b58String) {
    var b = base58CheckDecode(b58String);
    return utf8.decode(b);
  }

  dynamic b64Decode(dynamic b64) {
    // return jsonDecode(utf8.decode(base64.decode(b64)));
    return b64;
  }

  final TextEditingController _controller = TextEditingController();
  bool isEmpty = false;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _controller,
                maxLines: 7,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Enter text here..',
                    errorText: isEmpty ? 'Please enter text' : null),
                onChanged: (String value) {
                  if (value.isEmpty) {
                    setState(() {
                      isEmpty = true;
                    });
                  } else {
                    setState(() {
                      isEmpty = false;
                    });
                  }
                },
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_controller.text.isNotEmpty) {
                    debugPrint(_controller.text);
                    String conn = b58ToString(_controller.text);
                    Map<String, String> dApp = Map<String, String>.from(
                      jsonDecode(conn),
                    );

                    await bmw.onBeaconRequest((response) async {
                      debugPrint('onBeaconRequest = ${b64Decode(response)}');
                      switch (response['type']) {
                        case "TezosPermission":
                          bmw.sendResponse({
                            "id": response["id"],
                            "status": true,
                          }, (args) {});
                          break;
                        case "TezosOperation":
                          bmw.sendResponse({
                            "id": response["id"],
                            "status": true,
                            "transactionHash": "wow",
                          }, (args) {});
                          break;
                        case "TezosSignPayload":
                          bmw.sendResponse({
                            "id": response["id"],
                            "status": true,
                            "signature": "wow",
                          }, (args) {});
                          break;
                        case "TezosBroadcast":
                          bmw.sendResponse({
                            "id": response["id"],
                            "status": true,
                            "transactionHash": "wow",
                          }, (args) {});
                          break;
                        default:
                      }
                    });

                    await bmw.addPeer(dApp);

                    // await bmw.getPeers((response) {
                    //   debugPrint('getPeers = ${b64Decode(response)}');
                    // });

                    setState(() {
                      isEmpty = false;
                      _controller.text = '';
                    });
                  } else {
                    setState(() {
                      isEmpty = true;
                    });
                  }
                },
                child: const Text('Connect'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
