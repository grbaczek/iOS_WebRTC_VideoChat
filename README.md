# VideoChat

Hello world

```mermaid
sequenceDiagram
    participant Host
    participant Firebase
    Host->>Firebase: Create a chat channel
    Host->>Firebase: SDP offer
    Firebase->>Guest: SDP offer
    Guest->>Firebase: SDP answer
    Firebase->>Host: SDP answer
    Host->>Firebase: ICE candidate (Host)
    Firebase->>Guest: ICE candidate (Host)
    Guest->>Firebase: ICE candidate (Guest)
    Firebase->>Host: ICE candidate (Host)
```
