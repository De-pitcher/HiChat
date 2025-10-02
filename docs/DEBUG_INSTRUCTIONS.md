# Debugging User Search - Comprehensive Logging Added

## 🔍 **Logging Added To:**

### 1. **UserSearchService** (`lib/services/user_search_service.dart`)
- **Request logging**: URL, search term, auth token status
- **Response logging**: Status code, headers, full response body
- **Error logging**: Detailed error information with context
- **Parsing logging**: JSON parsing steps and results

### 2. **UserSearchScreen** (`lib/screens/user/user_search_screen.dart`)
- **Search input logging**: Query changes, debounce timing
- **Authentication logging**: Auth token status and user info
- **API call logging**: Request/response flow
- **State update logging**: UI state changes
- **Chat creation logging**: Full chat creation flow

### 3. **User Model** (`lib/models/user.dart`)
- **JSON parsing logging**: Individual user object parsing
- **Field extraction logging**: Each field parsing with values

## 📱 **How to View Logs:**

### **Method 1: Flutter DevTools (Recommended)**
1. Run your app in debug mode:
   ```bash
   flutter run --debug
   ```
2. Open Flutter DevTools in browser (URL will be shown in terminal)
3. Go to **Logging** tab
4. Filter by:
   - `UserSearchService` - API calls and responses
   - `UserSearchScreen` - UI interactions and state
   - `User` - User object parsing
   - `UserSearchResult` - Search result processing

### **Method 2: VS Code Debug Console**
1. Run app in debug mode from VS Code
2. Open **Debug Console** panel
3. All logs will appear with detailed error information

### **Method 3: Terminal Logs**
1. Run: `flutter run --debug`
2. All logs will appear in terminal with structured data

## 🚨 **What to Look For:**

### **Common Error Patterns:**

1. **Authentication Issues:**
   ```
   [UserSearchScreen] Auth token is null, throwing exception
   [UserSearchService] Authentication error (401)
   ```

2. **Network Issues:**
   ```
   [UserSearchService] Network or other error during search
   Error: Network error: [specific error]
   ```

3. **API Response Issues:**
   ```
   [UserSearchService] Unexpected status code
   [UserSearchService] Error parsing successful response
   ```

4. **JSON Parsing Issues:**
   ```
   [User] Error parsing User from JSON
   [UserSearchResult] Error parsing UserSearchResult
   ```

### **Successful Flow Logs:**
```
[UserSearchScreen] Starting search performance
[UserSearchService] Making search request  
[UserSearchService] Received search response (200)
[UserSearchResult] Successfully created UserSearchResult
[UserSearchScreen] Successfully updated UI state
```

## 🔧 **Log Levels:**
- **800**: Info/Debug messages
- **900**: Warnings  
- **1000**: Errors

## 📋 **Quick Debugging Steps:**

1. **Start the app in debug mode**
2. **Navigate to search screen** (tap + button)
3. **Type a search query**
4. **Watch the logs** for any errors
5. **Try creating a chat** with a found user

## 📊 **Sample Log Output:**

When you search for "john", you should see logs like:
```
[UserSearchScreen] Search input changed: {query: john, queryLength: 4}
[UserSearchService] Making search request: {url: https://chatcornerbackend-production.up.railway.app/api/users/search/?q=john}
[UserSearchService] Received search response: {statusCode: 200, responseBody: {...}}
[UserSearchResult] Successfully created UserSearchResult: {count: 2, results: 2 users}
```

## 🛠️ **Next Steps:**
1. Run the app and perform a search
2. Check the logs for any errors
3. Share the specific error logs you see
4. We can then fix the exact issue based on the detailed logging information

The comprehensive logging will show you exactly where the error occurs and what data is being processed at each step!