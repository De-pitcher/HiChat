package com.rodeni.hi_chat

import android.Manifest
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.Telephony
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SmsPlugin(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.hichat.sms_plugin"
        const val REQUEST_SMS_PERMISSION = 1001
    }

    private var methodChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun initialize(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "hasPermissions" -> hasPermissions(result)
            "readSms" -> readSms(call, result)
            "sendSms" -> sendSms(call, result)
            "getConversations" -> getConversations(result)
            else -> result.notImplemented()
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val permissions = arrayOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS
        )

        val permissionsToRequest = permissions.filter { permission ->
            ContextCompat.checkSelfPermission(activity, permission) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

        if (permissionsToRequest.isEmpty()) {
            result.success(true)
        } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(activity, permissionsToRequest, REQUEST_SMS_PERMISSION)
        }
    }

    // Handle permission request results
    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode == REQUEST_SMS_PERMISSION && pendingPermissionResult != null) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    private fun hasPermissions(result: MethodChannel.Result) {
        val hasReadSms = ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
        val hasSendSms = ContextCompat.checkSelfPermission(activity, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        val hasReceiveSms = ContextCompat.checkSelfPermission(activity, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        
        result.success(hasReadSms && hasSendSms && hasReceiveSms)
    }

    private fun readSms(call: MethodCall, result: MethodChannel.Result) {
        if (!hasReadSmsPermission()) {
            result.error("PERMISSION_DENIED", "SMS read permission not granted", null)
            return
        }

        try {
            val limit = call.argument<Int>("limit") ?: 1000 // Note: LIMIT removed from SQL to get all SMS
            val address = call.argument<String>("address")
            val startDate = call.argument<Int>("startDate")
            val endDate = call.argument<Int>("endDate")

            println("SmsPlugin: Reading ALL SMS messages (no limit applied to SQL), parameters: limit=$limit, address=$address, startDate=$startDate, endDate=$endDate")

            val smsList = mutableListOf<Map<String, Any>>()
            val contentResolver: ContentResolver = activity.contentResolver
            
            var selection: String? = null
            val selectionArgs = mutableListOf<String>()
            
            // Build selection criteria
            if (address != null) {
                selection = "address = ?"
                selectionArgs.add(address)
            }
            
            if (startDate != null) {
                selection = if (selection == null) "date >= ?" else "$selection AND date >= ?"
                selectionArgs.add(startDate.toString())
            }
            
            if (endDate != null) {
                selection = if (selection == null) "date <= ?" else "$selection AND date <= ?"
                selectionArgs.add(endDate.toString())
            }

            val cursor: Cursor? = contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms._ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.TYPE,
                    Telephony.Sms.READ,
                    Telephony.Sms.THREAD_ID
                ),
                selection,
                selectionArgs.toTypedArray(),
                "${Telephony.Sms.DATE} DESC" // Removed LIMIT to get ALL SMS messages
            )

            cursor?.use {
                var messageCount = 0
                val uniqueAddresses = mutableSetOf<String>()
                
                while (it.moveToNext()) {
                    val id = it.getLong(it.getColumnIndexOrThrow(Telephony.Sms._ID))
                    val address = it.getString(it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)) ?: ""
                    val body = it.getString(it.getColumnIndexOrThrow(Telephony.Sms.BODY)) ?: ""
                    val date = it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE))
                    val type = it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.TYPE))
                    val read = it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.READ)) == 1
                    val threadId = it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID))

                    // Track unique addresses
                    if (address.isNotEmpty()) {
                        uniqueAddresses.add(address)
                    }

                    val smsMap: Map<String, Any> = mapOf(
                        "id" to id,
                        "address" to address,
                        "body" to body,
                        "date" to date,
                        "type" to type,
                        "read" to read,
                        "threadId" to threadId,
                        "isSent" to (type == Telephony.Sms.MESSAGE_TYPE_SENT),
                        "isReceived" to (type == Telephony.Sms.MESSAGE_TYPE_INBOX)
                    )
                    smsList.add(smsMap)
                    messageCount++
                    
                    // Log first few messages for debugging
                    if (messageCount <= 5) {
                        println("SmsPlugin: SMS #$messageCount - ID:$id, Address:$address, Body:${body.take(30)}..., Date:$date, Type:$type, Read:$read, ThreadID:$threadId")
                    }
                }
                println("SmsPlugin: Total SMS messages found: $messageCount")
                println("SmsPlugin: Unique addresses found: ${uniqueAddresses.size}")
                println("SmsPlugin: Unique addresses: ${uniqueAddresses.toList().take(10)}")
            }

            // Convert to proper types for Flutter
            val flutterCompatibleList = smsList.map { smsMap ->
                hashMapOf<String, Any?>(
                    "id" to (smsMap["id"] as? Long),
                    "address" to (smsMap["address"] as? String ?: ""),
                    "body" to (smsMap["body"] as? String ?: ""),
                    "date" to (smsMap["date"] as? Long ?: 0L),
                    "type" to (smsMap["type"] as? Int ?: 1),
                    "read" to (smsMap["read"] as? Boolean ?: true),
                    "threadId" to (smsMap["threadId"] as? Long),
                    "isSent" to (smsMap["isSent"] as? Boolean ?: false),
                    "isReceived" to (smsMap["isReceived"] as? Boolean ?: false)
                )
            }
            
            println("SmsPlugin: Returning ${flutterCompatibleList.size} SMS messages to Flutter with proper types")
            result.success(flutterCompatibleList)
        } catch (e: Exception) {
            println("SmsPlugin: Error reading SMS: ${e.message}")
            e.printStackTrace()
            result.error("READ_SMS_ERROR", "Failed to read SMS: ${e.message}", null)
        }
    }

    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        if (!hasSendSmsPermission()) {
            result.error("PERMISSION_DENIED", "SMS send permission not granted", null)
            return
        }

        try {
            val phoneNumber = call.argument<String>("phoneNumber")
            val message = call.argument<String>("message")

            if (phoneNumber == null || message == null) {
                result.error("INVALID_ARGUMENTS", "Phone number and message are required", null)
                return
            }

            val smsManager = SmsManager.getDefault()
            
            // Split long messages if necessary
            val messageParts = smsManager.divideMessage(message)
            
            if (messageParts.size == 1) {
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            } else {
                smsManager.sendMultipartTextMessage(phoneNumber, null, messageParts, null, null)
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("SEND_SMS_ERROR", "Failed to send SMS: ${e.message}", null)
        }
    }

    private fun getConversations(result: MethodChannel.Result) {
        if (!hasReadSmsPermission()) {
            result.error("PERMISSION_DENIED", "SMS read permission not granted", null)
            return
        }

        try {
            val conversations = mutableListOf<Map<String, Any>>()
            val contentResolver: ContentResolver = activity.contentResolver

            // Query conversations (threads)
            val cursor: Cursor? = contentResolver.query(
                Uri.parse("content://mms-sms/conversations"),
                arrayOf(
                    "thread_id",
                    "snippet",
                    "msg_count",
                    "date"
                ),
                null,
                null,
                "date DESC"
            )

            cursor?.use {
                while (it.moveToNext()) {
                    val threadId = it.getLong(0)
                    val snippet = it.getString(1) ?: ""
                    val msgCount = it.getInt(2)
                    val date = it.getLong(3)

                    // Get the address for this conversation
                    val address = getAddressForThread(threadId)

                    val conversationMap: Map<String, Any> = mapOf(
                        "threadId" to threadId,
                        "address" to address,
                        "snippet" to snippet,
                        "messageCount" to msgCount,
                        "date" to date
                    )
                    conversations.add(conversationMap)
                }
            }

            // Convert to proper types for Flutter
            val flutterCompatibleConversations = conversations.map { convMap ->
                hashMapOf<String, Any?>(
                    "threadId" to (convMap["threadId"] as? Long),
                    "address" to (convMap["address"] as? String ?: ""),
                    "snippet" to (convMap["snippet"] as? String ?: ""),
                    "messageCount" to (convMap["messageCount"] as? Int ?: 0),
                    "date" to (convMap["date"] as? Long ?: 0L)
                )
            }
            
            result.success(flutterCompatibleConversations)
        } catch (e: Exception) {
            result.error("GET_CONVERSATIONS_ERROR", "Failed to get conversations: ${e.message}", null)
        }
    }

    private fun getAddressForThread(threadId: Long): String {
        val contentResolver: ContentResolver = activity.contentResolver
        val cursor: Cursor? = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS),
            "thread_id = ?",
            arrayOf(threadId.toString()),
            "${Telephony.Sms.DATE} DESC LIMIT 1"
        )

        cursor?.use {
            if (it.moveToFirst()) {
                return it.getString(0) ?: ""
            }
        }
        return ""
    }

    private fun hasReadSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasSendSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
    }
}