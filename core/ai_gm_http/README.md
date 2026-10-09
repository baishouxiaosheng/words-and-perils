# 可选真实AI接口模块 v1

状态：可配置源码 + 本地mock回归。**没有实际API凭据，也没有发生真实API调用。** ChatGPT会员不是本模块的API额度。当前main/default游戏入口没有接入本面板；人工JSON和署名样例路径不变。

## 文件与最小接线

- `core/ai_gm_http/client.gd`：Node，负责一次请求、严格绑定、唯一一次engine评估准备/只读叙事校验
- `http_transport.gd`：Godot HTTPRequest，HTTPS验证，禁止重定向，不重试
- `openai_chat_codec.gd`：Chat Completions JSON envelope；不执行tool/function calls
- `coast_contract.gd`：现有4个海岸resolver及临时规则的公开说明，不实现新规则
- `view/ai_connection_settings/panel.gd`：VBoxContainer；纯功能面板，暂未做主界面统一样式
- `tests/ai_gm_http/`：全部使用明确标识`mock_test_transport, live=false`的假transport

```gdscript
const AIClient = preload("res://core/ai_gm_http/client.gd")
const AISettings = preload("res://view/ai_connection_settings/panel.gd")
const CoastContract = preload("res://core/ai_gm_http/coast_contract.gd")
var ai = AIClient.new()
var settings = AISettings.new()

func install_ai():
    add_child(ai)
    add_child(settings)
    settings.bind_client(ai)
    settings.assessment_requested.connect(func():
        show_api_result(ai.request_assessment(adapter.engine, adapter.active_action, CoastContract.instructions())))
    settings.narration_requested.connect(func():
        var id = adapter.active_action if adapter.phase() == "staged" else adapter.last_action
        show_api_result(ai.request_narration(adapter.engine, id)))
    ai.assessment_ready.connect(func(_id, _reply):
        refresh_game_ui()) # already prepared ONCE; do not prepare again!
    ai.narration_ready.connect(func(_id, text):
        adapter.narration = text
        refresh_game_ui())
    ai.completed.connect(show_api_result)

func refresh_ai_controls():
    var display_phase = adapter.phase()
    if display_phase == "idle" and not adapter.last_action.is_empty():
        display_phase = "committed"
    settings.set_action_state(display_phase)
```

`show_api_result`应处理立即返回的错误与异步`completed`，按`ok/code/errors`显示。成功请求的立即结果不是模型完成证明。

**main须在新意图、读档、重置、切换世界/模式和离开当前结果显示前调用`ai.invalidate_context()`。** 请求期间不得调用人工导入/署名夹具准备；如允许则先取消请求。重复点击由client返回`BUSY`。失效响应不会重新评估或改世界。

client成功调用`engine.prepare_assessment(reply)`以后才发`assessment_ready`，main不得重复prepare。此时仅`ready_roll`，没有掷骰、暂存或提交。仍由既有明确按钮执行程序结算→stage→commit。叙事是可选只读过程，失败不影响已经确定的数值、回合、RNG或回执。

## 客户端API

- `configure(config, api_key) -> {ok,...}`：纯内存、无网络；必填`endpoint`（完整URL含路径）、实际`model`；`reasoning_effort`默认为空且不发送，`timeout_seconds`默认为30、范围1–120；`allow_localhost_http`默认为false
- `configured()`, `public_configuration()`, `provider_info()`：不返回密钥；“已配置”不等于真实服务可用
- `request_assessment(engine, action_id, trusted_instructions="")`、`request_narration(engine, action_id, trusted_instructions="")`：仅显式调用时发送；返回`ok/request_id/request_bytes/timeout_seconds`
- `busy()`、`request_summary()`：可显示当前公开JSON体积、超时与真假transport，绝不含密钥或内容
- `cancel()`、`invalidate_context()`、`clear_configuration()`：无重试；取消不保证服务端停止处理/计费
- `completed(result)`：所有异步成功/失败；含`phase/action_id/request_id/transport{provider,live}`。错误是固定可读说明，不反射响应正文或Authorization
- `assessment_ready(action_id, reply)`：原始结构化reply已通过现有engine；`narration_ready(action_id, text)`：已通过只读engine验证
- `busy_changed(bool)`：控制禁用按钮

传给`trusted_instructions`的内容只能是开发者已知的公开resolver/rule说明，不能附raw save、RNG、隐藏剧情、私有回执或密钥。真实请求数据只能由client内部调用engine的`model_request`/`narration_request`取得；没有`send_arbitrary_json`入口。

## 面板行为

`bind_client(client)`、`set_action_state(phase)`、`set_status(text)`；`assessment_requested`与`narration_requested`由main连接当前engine。设置按钮不会调用API。密钥为遮罩输入，应用后立即清空输入框；实际密钥仅在client内存，退出/清除时删除引用。没有文件写入或存档设置。GDScript字符串不提供可验证的安全内存擦除，因此不宣称抵御进程内存读取。

任何endpoint/model/reasoning/timeout/HTTP例外修改都先禁用请求按钮，重新应用后才能发送，避免显示新地址却发送旧服务。设置失败清空旧连接。API按钮明确说明可能计费；未勾选说明、无密钥或无实际model ID时不能调用。面板无后台/自动测试连接。主界面人工JSON仍须保留`live=false`限制；不能把粘贴JSON的`live=true`当作真正服务证明。

## Transport接口与扩展边界

```gdscript
signal completed(request_id: int, http_status: int, body: String, error_code: String)
func info() -> Dictionary: # {id: String, live: bool}
func send(request_id: int, endpoint: String, headers: PackedStringArray,
          body: String, timeout_seconds: float) -> Error:
func cancel(request_id: int) -> void:
```

`client.set_transport(custom_node)`注入预先受信任transport，忙时拒绝更换；不是模型任意选择工具的入口。mock明示`live=false`，绝不标成AI。HTTP transport的`openai_compatible_http, live=true`只表示确实使用HTTP；不保证提供商背后是哪种模型。真实返回provenance必须匹配此通道，不能自己宣称fixture/别家服务。

只实现一个可配置的Chat Completions JSON模式：`model`, `messages`, `response_format:{type:json_object}`, `stream:false`, `store:false`及可选`reasoning_effort`。不默认为所有服务兼容。实际endpoint、API model ID、reasoning支持、JSON mode及store字段支持须由提供商确认；不自动替换用户选择的模型。其他 provider 需以后新增明确适配器。
