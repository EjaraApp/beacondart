package africa.ejara.beacondart

import android.app.Activity
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import it.airgap.beaconsdk.blockchain.tezos.data.TezosAccount
import it.airgap.beaconsdk.blockchain.tezos.data.TezosNetwork
import it.airgap.beaconsdk.blockchain.tezos.message.request.BroadcastTezosRequest
import it.airgap.beaconsdk.blockchain.tezos.message.request.OperationTezosRequest
import it.airgap.beaconsdk.blockchain.tezos.message.request.PermissionTezosRequest
import it.airgap.beaconsdk.blockchain.tezos.message.request.SignPayloadTezosRequest
import it.airgap.beaconsdk.blockchain.tezos.message.response.BroadcastTezosResponse
import it.airgap.beaconsdk.blockchain.tezos.message.response.OperationTezosResponse
import it.airgap.beaconsdk.blockchain.tezos.message.response.PermissionTezosResponse
import it.airgap.beaconsdk.blockchain.tezos.message.response.SignPayloadTezosResponse
import it.airgap.beaconsdk.blockchain.tezos.tezos
import it.airgap.beaconsdk.client.wallet.BeaconWalletClient
import it.airgap.beaconsdk.client.wallet.compat.*
import it.airgap.beaconsdk.core.data.P2pPeer
import it.airgap.beaconsdk.core.data.Peer
import it.airgap.beaconsdk.core.data.BeaconError
import it.airgap.beaconsdk.core.message.*
import it.airgap.beaconsdk.transport.p2p.matrix.p2pMatrix
import africa.ejara.beacondart.utils.toJson

/** BeacondartPlugin */
class BeacondartPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var activity: Activity

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "beacondart")
    channel.setMethodCallHandler(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
  }

  override  fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
  }

  override fun onDetachedFromActivity() {
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "addPeer" -> {
        val peerInfo: Map<String, String>? = call.arguments()
        addPeer(peerInfo!!)
        result.success(true)
      }
      "removePeer" -> {
        val peerPublicKey: String = call.arguments()!!
        removePeer(peerPublicKey)
        result.success(true)
      }
      "removePeers" -> {
        removePeers()
        result.success(true)
      }
      "getPeers" -> {
        val callBackId: Int =  call.arguments()!!
        getPeers(callBackId)
        result.success(true)
      }
      "onBeaconRequest" -> {
        beaconListenerReady = true
        result.success(true)
      }
      "sendResponse" -> {
        val args: Map<String, String> = call.arguments()!!
        sendResponse(args)
        result.success(true)
      }
      "startBeacon" -> {
        val args: Map<String, Any> = call.arguments()!!
        startBeacon(args["appName"] as String, args["publicKey"] as String, args["address"] as String, args["callBackId"] as Int)
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  lateinit var beaconWallet: BeaconWalletClient

  private val callbacksById: MutableMap<Int, (Map<String, Any>) -> Unit> = mutableMapOf()

  var callBackId: Int = 1

  var beaconListenerReady: Boolean = false

  private val beaconCallBackId: Int = 0

  private fun nextCallBackId(): Int {
    callBackId += 1
    return callBackId
  }

  private fun sendRequest(params: Any, callId: Int = beaconCallBackId) {
    val resp: Map<String, Any> = mapOf("id" to callId, "args" to params)
    activity.runOnUiThread(Runnable { channel.invokeMethod("callListener", resp) })
  }

  private fun registerCallBack(callBack: (Map<String, Any>) -> Unit) : Int {
    val id: Int = nextCallBackId()
    callbacksById[id] = callBack
    return id
  }

  private fun execCallBack(params: Map<String, Any>) {
    val id: Int = params["id"] as Int
    callbacksById[id]?.invoke(params)
    callbacksById.remove(id)
  }

  private fun addPeer(peerInfo: Map<String, String>) {
    val peer = P2pPeer(
            id = peerInfo["id"]!!,
            name = peerInfo["name"]!!,
            publicKey = peerInfo["publicKey"]!!,
            relayServer = peerInfo["relayServer"]!!,
            version = peerInfo["version"]!!,
    )
    beaconWallet.addPeers(peer, callback = object : SetCallback {
      override fun onSuccess() {
        println("Peer added successfully ...")
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  private fun removePeer(peerPublicKey: String) {

    beaconWallet.getPeers(callback = object : GetCallback<List<Peer>> {
      override fun onSuccess(peers: List<Peer>) {
        val ps: List<Peer> = peers.filter { it.publicKey == peerPublicKey }
        beaconWallet.removePeers(ps, callback = object : SetCallback {
          override fun onSuccess() {
            println("Peer removed successfully ...")
          }

          override fun onError(error: Throwable) {
            error.printStackTrace()
          }
        })
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  private fun removePeers() {
    beaconWallet.removeAllPeers(callback = object : SetCallback {
      override fun onSuccess() {
        println("All peers removed successfully ...")
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  private fun getPeers(callBackId: Int) {
    beaconWallet.getPeers(callback = object : GetCallback<List<Peer>> {
      override fun onSuccess(peers: List<Peer>) {
        val jsonPeers: List<String> = peers.map { it.toJson().toString() }
        val resp: Map<String, Any> = mapOf("id" to callBackId, "args" to jsonPeers)
        sendRequest(resp, callBackId)
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  private fun startBeacon(appName: String, publicKey: String, address: String, callBackId: Int) {
    BeaconWalletClient.Builder(appName).apply {
      support(tezos())
      use(p2pMatrix())
    }.build(object : BuildCallback {
      override fun onSuccess(beaconClient: BeaconWalletClient) {
        beaconWallet = beaconClient
        subscribeToRequests(publicKey, address)
        sendRequest(true, callBackId)
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
        sendRequest(false, callBackId)
      }
    })
  }

  fun subscribeToRequests(publicKey: String, address: String) {
    beaconWallet.connect(listener = object: OnNewMessageListener {
      override fun onNewMessage(message: BeaconMessage) {
        onBeaconRequest(message, publicKey, address)
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  fun onBeaconRequest(message: BeaconMessage, publicKey: String, address: String) {
    onTezosRequest(message, publicKey, address)
  }

  private fun onTezosRequest(message: BeaconMessage, publicKey: String, address: String) {
    when (message) {
      is PermissionTezosRequest -> handleTezosPermission(message, publicKey, address)
      is OperationTezosRequest -> handleTezosOperation(message)
      is SignPayloadTezosRequest -> handleTezosSignPayload(message)
      is BroadcastTezosRequest -> handleTezosBroadcast(message)
      is BeaconRequest -> ErrorBeaconResponse.from(message, BeaconError.Aborted)
    }
  }

  private fun handleTezosPermission(message: PermissionTezosRequest, publicKey: String, address: String) {
    val id = registerCallBack {
      val status = it["status"] as Boolean
      val response = if (!status) {
        ErrorBeaconResponse.from(message, BeaconError.Aborted)
      } else {
          val account = tezosAccount(message.network, publicKey, address)
        PermissionTezosResponse.from(message, account)
      }
      sendTezosResponse(response)
    }

    sendRequest(mapOf(
      "id" to id,
      "type" to "TezosPermission",
      "data" to message.toJson().toString()
    ))
  }

  private fun handleTezosOperation(message: OperationTezosRequest) {
    val id = registerCallBack {
      val status = it["status"] as Boolean
      val response = if (!status) {
        ErrorBeaconResponse.from(message, BeaconError.Aborted)
      } else {
        val transactionHash = it["transactionHash"] as String
        OperationTezosResponse.from(message, transactionHash)
      }
      sendTezosResponse(response)
    }

    sendRequest(mapOf(
      "id" to id,
      "type" to "TezosOperation",
      "data" to message.toJson().toString()
    ))
  }

  private fun handleTezosSignPayload(message: SignPayloadTezosRequest) {
    val id = registerCallBack {
      val status = it["status"] as Boolean
      val response = if (!status) {
        ErrorBeaconResponse.from(message, BeaconError.Aborted)
      } else {
        val signature = it["signature"] as String
        SignPayloadTezosResponse.from(message, message.signingType, signature)
      }
      sendTezosResponse(response)
    }

    sendRequest(mapOf(
      "id" to id,
      "type" to "TezosSignPayload",
      "data" to message.toJson().toString()
    ))
  }

  private fun handleTezosBroadcast(message: BroadcastTezosRequest) {
    val id = registerCallBack {
      val status = it["status"] as Boolean
      val response = if (!status) {
        ErrorBeaconResponse.from(message, BeaconError.Aborted)
      } else {
        val transactionHash = it["transactionHash"] as String
        BroadcastTezosResponse.from(message, transactionHash)
      }
      sendTezosResponse(response)
    }

    sendRequest(mapOf(
      "id" to id,
      "type" to "TezosBroadcast",
      "data" to message.toJson().toString()
    ))
  }

  private fun sendTezosResponse(response: BeaconResponse) {
    beaconWallet.respond(response, callback = object: ResponseCallback {
      override fun onSuccess() {
        println("Response sent ...")
      }

      override fun onError(error: Throwable) {
        error.printStackTrace()
      }
    })
  }

  private fun sendResponse(from: Map<String, Any>) {
    execCallBack(from)
  }

  private fun tezosAccount(network: TezosNetwork, publicKey: String, address: String): TezosAccount = TezosAccount(
    publicKey,
    address,
    network,
  )

}
