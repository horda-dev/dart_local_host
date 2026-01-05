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
