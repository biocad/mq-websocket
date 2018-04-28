# mq-websocket

## Contracts

**Remark.** 
All the messages described below are considered to be ByteStrings.

The first message from the WebSocket client after establishing the connection must me a JSON with the single field `specs` containing all `spec` which he wants to listen. If the client wants to receive all specs, the field should be left empty. Example:

```JSON
{
  "specs" : ["example_speaker", "ss_worker_ab_fold"]
}
```

or 

```JSON
{
  "specs" : []
}
```

All other messages should be packed in MessagePack representation of a dictionary with two keys:
  * `tag` : a ByteString message tag.
  * `message` : a ByteString message.

Client will receive message in this representation too.

## Ping

We have implemented a hardcode ping alongside the one from WebSocket so that the connections __really__ stays alive. User may send a `"ping"` ByteString and should receive `"pong"` in response.
Both ping and pong messages are packed in MessagePack ByteStrings. So we do expect the following binary representations of these messages:
  * `ping` : `\xc4\x04ping`
  * `pong` : `\xc4\x04pong`

Here \xAA is sybol with hexadecimal number AA in the ASCII table.
