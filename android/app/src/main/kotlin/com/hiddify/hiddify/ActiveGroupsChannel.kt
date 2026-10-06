package com.hiddify.hiddify

import android.util.Log
import com.google.gson.Gson
import com.hiddify.hiddify.utils.CommandClient
import com.hiddify.hiddify.utils.ParsedOutboundGroup
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.nekohasekai.libbox.OutboundGroup
import kotlinx.coroutines.CoroutineScope


class ActiveGroupsChannel(private val scope: CoroutineScope) : FlutterPlugin,
    CommandClient.Handler {
    companion object {
        const val TAG = "A/ActiveGroupsChannel"
        const val CHANNEL = "com.hiddify.app/active-groups"
        val gson = Gson()
    }

    private val client =
        CommandClient(scope, CommandClient.ConnectionType.GroupOnly, this)

    private var channel: EventChannel? = null
    private var event: EventChannel.EventSink? = null

    override fun updateGroups(groups: List<OutboundGroup>) {
        try {
            MainActivity.instance.runOnUiThread {
                try {
                    val parsedGroups = groups.mapNotNull { group ->
                        try {
                            ParsedOutboundGroup.fromOutbound(group)
                        } catch (e: Exception) {
                            Log.e(TAG, "failed parsing active group", e)
                            null
                        }
                    }
                    event?.success(gson.toJson(parsedGroups))
                } catch (e: Exception) {
                    Log.e(TAG, "failed sending active groups event", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "failed updating active groups", e)
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            CHANNEL
        )

        channel!!.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                event = events
                Log.d(TAG, "connecting active groups command client")
                client.connect()
            }

            override fun onCancel(arguments: Any?) {
                event = null
                Log.d(TAG, "disconnecting active groups command client")
                client.disconnect()
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        event = null
        client.disconnect()
        channel?.setStreamHandler(null)
    }
}