import Flutter
import UIKit

import BeaconCore
import BeaconBlockchainSubstrate
import BeaconBlockchainTezos
import BeaconClientWallet
import BeaconTransportP2PMatrix

public class SwiftBeacondartPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "beacondart", binaryMessenger: registrar.messenger())
    let instance = SwiftBeacondartPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    
    switch call.method {
        case "addPeer":
            let peerInfo = call.arguments as! [String: String]
            addPeer(peerInfo: peerInfo)
            result(true)
        case "removePeer":
            let peerPublicKey = call.arguments as! String
            removePeer(peerPublicKey: peerPublicKey)
            result(true)
        case "removePeers":
            removePeers()
            result(true)
        case "getPeers":
            let callBackId = call.arguments as! Int
            getPeers{ result in
                
                switch result {
                    case let .success(peers):
                    let resp: [String: Any] = ["id": callBackId, "args": peers]
                        self.channel!.invokeMethod("callListener", arguments: resp);
                    case  .failure(_):
                        return
                }
            }
            result(nil)
        case "onBeaconRequest":
            beaconListenerReady = true
            result(true)
        case "sendResponse":
            let args = call.arguments as! [String: Any]
            sendResponse(from: args)
            result(true)
        case "startBeacon":
            let args = call.arguments as! [String: Any]
            startBeacon(appName: args["appName"] as! String, publicKey: args["publicKey"] as! String, address: args["address"] as! String, completion: {res in
                switch res {
                case  .success(_):
                    let resp: [String: Any] = ["id": args["callBackId"] as! Int, "args": true]
                    self.channel!.invokeMethod("callListener", arguments: resp)
                case  .failure(_):
                    let resp: [String: Any] = ["id": args["callBackId"] as! Int, "args": false]
                    self.channel!.invokeMethod("callListener", arguments: resp)
                }
            })
            result(true)
        default:
            result(FlutterMethodNotImplemented)
      }
  }
    
    var beaconWallet: Beacon.WalletClient!
    
    var callbacksById: [Int: ([String:Any]) -> Void] = [:]
    
    var callBackId: Int = 1
    
    var beaconListenerReady: Bool = false
    
    var channel: FlutterMethodChannel?
    
    let beaconCallBackId: Int = 0
    
    func nextCallBackId() -> Int {
        callBackId += 1
        return callBackId
    }
    
    func sendRequest(params: [String: Any]) {
        let resp: [String: Any] = ["id": beaconCallBackId, "args": params]
        self.channel!.invokeMethod("callListener", arguments: resp)
    }
    
    func registerCallBack(callBack: @escaping ([String:Any]) -> Void) -> Int {
        let id: Int = nextCallBackId()
        callbacksById[id] = callBack
        return id
    }
    
    func execCallBack(params: [String:Any]) {
        let id: Int = params["id"] as! Int
        callbacksById[id]!(params)
        callbacksById.removeValue(forKey: id)
    }
        
    func addPeer(peerInfo: [String: String]) {
        let peer = Beacon.P2PPeer(
            id: peerInfo["id"]!,
            name: peerInfo["name"]!,
            publicKey: peerInfo["publicKey"]!,
            relayServer: peerInfo["relayServer"]!,
            version: peerInfo["version"]!
        )
        beaconWallet.add([.p2p(peer)]) { _ in }
    }
    
    func removePeer(peerPublicKey: String) {
        beaconWallet.removePeer(withPublicKey: peerPublicKey) { _ in }
    }
    
    func removePeers() {
        beaconWallet.removeAllPeers { _ in }
    }
    
    func getPeers(completion: @escaping (Result<String, Error>) -> ()) {
        beaconWallet.getPeers{ result in
            switch result {
            case let .success(peers):
                completion(.success(self.toJsonB64(from: peers)))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
    
    func tezosAccount(network: Tezos.Network, publicKey: String, address: String) throws -> Tezos.Account {
        try Tezos.Account(
            publicKey: publicKey,
            address: address,
            network: network
        )
    }

    func startBeacon(appName: String, publicKey: String, address: String, completion: @escaping (Result<(), Error>) -> ()) {
        print("startBeacon")
        createBeaconWallet(appName: appName, completion: { result in
                guard case .success(_) = result else {
                    return
                }
                switch result {
                case  .success(_):
                    completion(.success(()))
                case let .failure(error):
                    completion(.failure(error))
                }

                self.subscribeToRequests(publicKey: publicKey, address: address, completion:  { result in
                    guard case .success(_) = result else {
                        return
                    }
                    switch result {
                    case  .success(_):
                        completion(.success(()))
                    case let .failure(error):
                        completion(.failure(error))
                    }
                })
        })
    }

    func createBeaconWallet(appName: String, completion: @escaping (Result<(), Error>) -> ()) {
        do {
            Beacon.WalletClient.create(
                with: .init(
                    name: appName,
                    blockchains: [Tezos.factory],
                    connections: [try Transport.P2P.Matrix.connection()]
                )
            ) { result in
                switch result {
                case let .success(client):
                    self.beaconWallet = client
                    completion(.success(()))
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func subscribeToRequests(publicKey: String, address: String, completion: @escaping (Result<(), Error>) -> ()) {
        beaconWallet.connect { result in
            switch result {
            case .success(_):
                self.beaconWallet.listen(onRequest: self.onBeaconRequest(publicKey: publicKey, address: address))
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func onBeaconRequest(publicKey: String, address: String) -> ((Result<BeaconRequest<Tezos>, Beacon.Error>) -> Void){
        return { (_ request: Result<BeaconRequest<Tezos>, Beacon.Error>) in
            do {
                let request = try request.get()
                self.onTezosRequest(from: request, publicKey: publicKey, address: address)
            } catch {
                print(error)
            }
        }
    }
    
    func onTezosRequest(from request: BeaconRequest<Tezos>, publicKey: String, address: String) -> Void {
        do {
            let res = try self.tezosResponse(from: request, publicKey: publicKey, address: address)
            switch res.type {
                case .Permission:
                    self.handleTezosPermission(from: res.response, publicKey: publicKey, address: address)
                case .Operation:
                    self.handleTezosOperation(from: res.response)
                case .SignPayload:
                    self.handleTezosSignPayload(from: res.response)
                case .Broadcast:
                    self.handleTezosBroadcast(from: res.response)
            }
        } catch {
            print(error)
        }
            
    }
    
    func handleTezosBroadcast(from request: BeaconRequestProtocol) -> Void {
        let content = request as! BroadcastTezosRequest
        let id: Int = self.registerCallBack(callBack: { (params: [String:Any]) -> Void in
            let status = params["status"] as! Bool
            if status == false {
                return
            }
            let transactionHash = params["transactionHash"] as! String
            let response = BeaconResponse<Tezos>.blockchain(.broadcast(BroadcastTezosResponse(from: content, transactionHash: transactionHash)))
            self.sendTezosResponse(from: response)
        })
        self.sendRequest(params: [
            "id": id,
            "type": "TezosBroadcast",
            "data": self.toJsonB64(from: content)
        ])
    }
    
    func handleTezosSignPayload(from request: BeaconRequestProtocol) -> Void {
        let content = request as! SignPayloadTezosRequest
        let id: Int = self.registerCallBack(callBack: { (params: [String:Any]) -> Void in
            let status = params["status"] as! Bool
            if status == false {
                return
            }
            let signature = params["signature"] as! String
            let response = BeaconResponse<Tezos>.blockchain(.signPayload(SignPayloadTezosResponse(from: content, signature: signature)))
            self.sendTezosResponse(from: response)
        })
        self.sendRequest(params: [
            "id": id,
            "type": "TezosSignPayload",
            "data": self.toJsonB64(from: content)
        ])
    }
    
    func handleTezosOperation(from request: BeaconRequestProtocol) -> Void {
        let content = request as! OperationTezosRequest
        let id: Int = self.registerCallBack(callBack: { (params: [String:Any]) -> Void in
            let status = params["status"] as! Bool
            if status == false {
                return
            }
            let transactionHash = params["transactionHash"] as! String
            let response = BeaconResponse<Tezos>.blockchain(.operation(OperationTezosResponse(from: content, transactionHash: transactionHash)))
            self.sendTezosResponse(from: response)
        })
        
        self.sendRequest(params: [
            "id": id,
            "type": "TezosOperation",
            "data": self.toJsonB64(from: content)
        ])
    }
    
    func handleTezosPermission(from request: BeaconRequestProtocol, publicKey: String, address: String) -> Void {
        let content = request as! PermissionTezosRequest
        let id: Int = self.registerCallBack(callBack: { (params: [String:Any]) -> Void in
            do {
                let status = params["status"] as! Bool
                if status == false {
                    return
                }
                let account = try self.tezosAccount(network: content.network, publicKey: publicKey, address: address)
                let response = BeaconResponse<Tezos>.permission(PermissionTezosResponse(from: content, account: account))
                self.sendTezosResponse(from: response)
            } catch {
                print(error)
            }
            
        })
        self.sendRequest(params: [
            "id": id,
            "type": "TezosPermission",
            "data": self.toJsonB64(from: content)
        ])
    }
    
    func sendTezosResponse(from response: BeaconResponse<Tezos>) -> Void {
        self.beaconWallet.respond(with: response) { result in
            switch result {
            case .success(_):
                print("Response sent")
            case let .failure(error):
                print(error)
            }
        }
    }

    func tezosResponse(from request: BeaconRequest<Tezos>, publicKey: String, address: String) throws -> (type: TezosBeaconRequest, response: BeaconRequestProtocol) {
         
        switch request {
        case let .permission(content):
            return (TezosBeaconRequest.Permission, content)
        case let .blockchain(blockchain):
            switch blockchain {
            case let .operation(content):
                return (TezosBeaconRequest.Operation, content)
            case let .signPayload(content):
                return (TezosBeaconRequest.SignPayload, content)
            case let .broadcast(content):
                return (TezosBeaconRequest.Broadcast, content)
            }
        }
    }
    
    func sendResponse(from object: [String: Any]) {
        self.execCallBack(params: object)
    }
    
    func toJsonB64<T: Encodable>(from content: T) -> String {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(content)
            return String(data: encoded, encoding: .utf8) ?? ""
        } catch {
            print("encode error = ", error)
            return ""
        }
    }
    
}

enum TezosBeaconRequest {
    case Permission
    case Operation
    case SignPayload
    case Broadcast
}
