package com.hiddify.hiddify

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel


class LogHandler : FlutterPlugin {

    companion object {
        const val TAG = "A/LogHandler"
        const val SERVICE_LOGS = "com.hiddify.app/service.logs"
    }

    private lateinit var logsChannel: EventChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        logsChannel = EventChannel(flutterPluginBinding.binaryMessenger, SERVICE_LOGS)

        logsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val activity = MainActivity.instance
                activity.runOnUiThread {
                    val logsCopy = synchronized(activity.logList) {
                        ArrayList(activity.logList)
                    }
                    events?.success(logsCopy)
                }
                activity.logCallback = {
                    activity.runOnUiThread {
                        val logsCopy = synchronized(activity.logList) {
                            ArrayList(activity.logList)
                        }
                        events?.success(logsCopy)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                MainActivity.instance.logCallback = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    }
}