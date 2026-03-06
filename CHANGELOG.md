## 0.11.1

- **FIX**: replace stream timeouts with warning logs to prevent server crash on long running processes and command handlers

## 0.11.0

- **FEAT**: auth through a process func (client must use horda_client >= 0.30.0)

## 0.10.0

- **BREAKING**: split change tracking into view and query changes (publishChange → publishViewChange/publishQueryChange)
- **BREAKING**: use positions instead of keys for RefListView
- **FIX**: fix items being added to pages which are unaffected by the change
- **FEAT**: update horda_core to 0.21.0
- **FEAT**: update horda_server to 0.23.0

## 0.9.0

- **FEAT**: add process scheduling via EntityContext
- **DEPRECATION**: deprecated command scheduling API in ProcessContext
- **CHORE**: update horda_server to 0.22.0

## 0.8.1

- **FIX**: run business processes on entity events
- **FIX**: fix attribute change projection
- **FIX**: fix entity/service calls not throwing on failure in some cases
- **FIX**: handle uncaught exceptions in process funcs crashing the server
- **CHORE**: update dependencies

## 0.8.0

- **FEAT**: add pagination with real-time sync for ref list views
- **BREAKING**: ref list view values are now key-value pairs (ListItem) instead of plain strings
- **CHORE**: update horda_core to 0.20.0
- **CHORE**: update horda_server to 0.21.0

## 0.7.0

- **FEAT**: support atomic query and subscribe
- **CHORE**: update horda_core to 0.18.0
- **CHORE**: update horda_server to 0.19.0

## 0.6.0

- **FEAT**: support multiple process groups
- **FEAT**: detect process groups with process funcs which handle the same event type across multiple process groups

## 0.5.0

- **BREAKING**: rename FlowResult to ProcessResult
- **FEAT**: update horda_core to 0.17.0
- **FEAT**: update horda_server to 0.18.0

## 0.4.0

- **FIX**: allow sending and calling commands when user is incognito
- **FEAT**: use nullable EntityContext.senderId
- **FEAT**: use horda_server 0.17.0

## 0.3.0

- **FEAT**: support WebSocket connection on web platform

## 0.2.0

- **FEAT**: add singleton entity support with automatic pre-initialization

## 0.1.0

- initial version
