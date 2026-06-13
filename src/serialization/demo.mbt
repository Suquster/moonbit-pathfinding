// demo.mbt —— 端到端实战 demo（旗舰深化，旁路新增，R9）。
//
// 设计依据（design.md §4.9「端到端实战 demo」）：提供一份贯穿文档与基准的实战
// `.proto`（"用户档案" UserProfile），覆盖标量 / repeated / 嵌套消息 / enum /
// oneof / map 六类构造（R9.1），并给出与之匹配的样例消息 `demo_message`，用于演示
// `parse_proto_full` → `validate_schema` → `gen_moonbit_full` → `encode_typed` →
// `decode_typed` → JSON 往返的端到端流程（R9.2/9.3）。

///|
/// 贯穿文档与基准的实战 `.proto`：覆盖标量 / repeated / 嵌套消息 / enum / oneof /
/// map 六类构造（R9.1）。
pub fn demo_proto() -> String {
  (
    #|syntax = "proto3";
    #|
    #|enum Status {
    #|  STATUS_UNKNOWN = 0;
    #|  STATUS_ACTIVE = 1;
    #|  STATUS_BANNED = 2;
    #|}
    #|
    #|message Address {
    #|  string city = 1;
    #|  string zip = 2;
    #|}
    #|
    #|message UserProfile {
    #|  int32 id = 1;
    #|  string name = 2;
    #|  repeated string tags = 3;
    #|  Status status = 4;
    #|  Address address = 5;
    #|  oneof contact {
    #|    string email = 6;
    #|    string phone = 7;
    #|  }
    #|  map<string, int32> metadata = 8;
    #|  double score = 9;
    #|}
  )
}

///|
/// 与 `demo_proto` 匹配的样例消息（UserProfile）。
///
/// 设置 id/name/tags/status/address/email(oneof)/metadata/score；phone（oneof
/// 另一成员）保持未设置。各标量取非默认值以保证编码非省略、往返可见证。
pub fn demo_message() -> TypedMessage {
  let address = TypedMessage::new()
    .set(1, TStringV("Berlin"))
    .set(2, TStringV("10115"))
  TypedMessage::new()
  .set(1, TInt(42L))
  .set(2, TStringV("Ada"))
  .set(3, TList([TStringV("admin"), TStringV("dev")]))
  .set(4, TEnumV(1))
  .set(5, TMsg(address))
  .set(6, TStringV("ada@example.com"))
  .set(8, TMap([(TStringV("level"), TInt(7L))]))
  .set(9, TDoubleV(1.5))
}

///|
/// demo 中根消息的限定名。
pub let demo_message_name : String = "UserProfile"
