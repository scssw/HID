package com.hiddify.hiddify.utils

import com.google.gson.annotations.SerializedName
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupItem

data class ParsedOutboundGroup(
    @SerializedName("tag") val tag: String,
    @SerializedName("type") val type: String,
    @SerializedName("selected") val selected: String,
    @SerializedName("items") val items: List<ParsedOutboundGroupItem>
) {
    companion object {
        fun fromOutbound(group: OutboundGroup?): ParsedOutboundGroup {
            if (group == null) {
                return ParsedOutboundGroup("", "", "", emptyList())
            }
            val items = mutableListOf<ParsedOutboundGroupItem>()
            try {
                val outboundItems = group.items
                if (outboundItems != null) {
                    while (outboundItems.hasNext()) {
                        val item = outboundItems.next()
                        if (item != null) {
                            items.add(ParsedOutboundGroupItem(item))
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("OutboundMapper", "failed parsing outbound items for group: ${group.tag}", e)
            }
            return ParsedOutboundGroup(
                group.tag ?: "",
                group.type ?: "",
                group.selected ?: "",
                items
            )
        }
    }
}

data class ParsedOutboundGroupItem(
    @SerializedName("tag") val tag: String,
    @SerializedName("type") val type: String,
    @SerializedName("url-test-delay") val urlTestDelay: Int,
) {
    constructor(item: OutboundGroupItem) : this(
        item.tag ?: "",
        item.type ?: "",
        item.urlTestDelay
    )
}