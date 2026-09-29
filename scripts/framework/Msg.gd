## 消息类型枚举 —— 对应 Framework.Message.MessageType
## C# 侧是 enum，GDScript 用常量整数表示，语义与顺序完全一致。
class_name Msg
extends RefCounted

enum T {
	Null,
	OnConnect,
	OnDisconnect,
	OnReconnect,
	OnUICreate,
	OnUIDestroy,
	OnUIShow,
	OnUIHide,
	OnUIPause,
	OnUIResume,
	REGISTERREQUEST,
	REGISTERRESPONSE,
	LOGINREQUEST,
	LOGINRESPONSE,
	LOGOUTREQUEST,
	LOGOUTRESPONSE,
	ROOMLISTREQUEST,
	ROOMLISTRESPONSE,
	ROOMINFO,
	RANKINGRESPONSE,
	RANKINFOREQUEST,
	RANKINFORESPONSE,
	CREATEROOMREQUEST,
	ENTERROOMREQUEST,
	LEAVEROOMREQUEST,
	JOINTEAMREQUEST,
	READYFORGAMEREQUEST,
	SINGLEPLAYERINFO,
	GAMEINFO,
	TALK,
	GOSSIP,
	ERROR,
	HEARTBEAT,
	LEADERREQUEST,
	LEADERRESPONSE,
	POLLINGREQUEST,
	POLLINGRESPONSE,
	ROLEREQUEST,
	PICKBAN,
	ACTION,
	RESPOND,
	COMMANDREQUEST,
	ERRORINPUT,
	HITMSG,
	TURNBEGIN,
	CARDMSG,
	HURTMSG,
	SKILLMSG,
	HERORANKREQUEST,
	HERORANKRESPONSE,
	GIVEUPREQUEST,
	GIVEUPRESPONSE,
	LoginState,
	RoomList,
	InputBox,
	EnterRoom,
	RoomIDChange,
	GameStart,
	ChooseRole,
	MoraleChange,
	ShowCardChange,
	GemChange,
	CrystalChange,
	GrailChange,
	SendHint,
	Win,
	Lose,
	PlayerLeave,
	PlayerHeroName,
	PlayerRoleChange,
	PlayerTeamChange,
	PlayerHandChange,
	PlayerHealChange,
	PlayerEnergeChange,
	PlayerTokenChange,
	PlayerKneltChange,
	PlayerNickName,
	PlayerIsReady,
	PlayerBasicAndExCardChange,
	PlayerActionChange,
	LogChange,
	ChatChange,
	AgentSelectCard,
	AgentSelectPlayer,
	AgentSelectSkill,
	AgentSelectArgs,
	AgentStateChange,
	AgentUIStateChange,
	AgentHandChange,
	RecHandChange,
	AgentUpdate,
	ShowNewArgsUI,
	CloseNewArgsUI,
	PlayBGM,
	RestTurnBG,
	StartDisCon,
	StopDisCon,
	OptionClose,
	OptionText,
}

## 窗口类型 —— 对应 Framework.UI.WindowType
enum W {
	None,
	ArgsUI,
	BattleUIMobile,
	ChooseArgsUI,
	ChooseEnergy,
	CreateRoomUI,
	DisConnectedPoll,
	HandBook,
	InfomationUI,
	InputBox,
	Lobby,
	LoginBox,
	OptionsUI,
	ReadyRoom,
	ReConBox,
	RoleChoose31,
	RoleChooseAny,
	RoleChooseBPCM,
	RoleChooseBar,
	RoomChatUI,
	SpecialActionUI,
	Loading,
	BattleRecord,
	HeroRank,
	RecordWindow,
	RegistBox,
}

## 窗口消息 —— 对应 Framework.UI.WinMsg
enum Win {
	None,
	Show,
	Hide,
	Pause,
	Resume,
	Destroy,
}

## ---------------------------------------------------------------------------
## 线上协议号（ProtoNameIds） -> 客户端事件号（Msg.T）
##
## 两套编号并不相同：ProtoNameIds 是 C# 服务端协议的线上编号，Msg.T 是本客户端
## 内部的事件枚举（例如线上 GAMEINFO=16，而 Msg.T.GAMEINFO=28，与线上 ROOMINFO 撞号）。
## 对应 C# 里拿到 protobuf 类型后按「类型」派发，而不是直接把协议号当事件号用，
## 所以收包必须先过这张表，否则房间信息会被当成对局信息处理。
## ---------------------------------------------------------------------------
const PROTO_TO_EVENT := {
	ProtoNameIds.REGISTERRESPONSE: T.REGISTERRESPONSE,
	ProtoNameIds.LOGINRESPONSE: T.LOGINRESPONSE,
	ProtoNameIds.LOGOUTRESPONSE: T.LOGOUTRESPONSE,
	ProtoNameIds.ROOMLISTRESPONSE: T.ROOMLISTRESPONSE,
	ProtoNameIds.ROOMINFO: T.ROOMINFO,
	ProtoNameIds.RANKINGRESPONSE: T.RANKINGRESPONSE,
	ProtoNameIds.RANKINFORESPONSE: T.RANKINFORESPONSE,
	ProtoNameIds.SINGLEPLAYERINFO: T.SINGLEPLAYERINFO,
	ProtoNameIds.GAMEINFO: T.GAMEINFO,
	ProtoNameIds.TALK: T.TALK,
	ProtoNameIds.GOSSIP: T.GOSSIP,
	ProtoNameIds.ERROR: T.ERROR,
	ProtoNameIds.HEARTBEAT: T.HEARTBEAT,
	ProtoNameIds.LEADERREQUEST: T.LEADERREQUEST,
	ProtoNameIds.LEADERRESPONSE: T.LEADERRESPONSE,
	ProtoNameIds.POLLINGRESPONSE: T.POLLINGRESPONSE,
	ProtoNameIds.HERORANKRESPONSE: T.HERORANKRESPONSE,
	ProtoNameIds.GIVEUPRESPONSE: T.GIVEUPRESPONSE,
	ProtoNameIds.ROLEREQUEST: T.ROLEREQUEST,
	ProtoNameIds.PICKBAN: T.PICKBAN,
	ProtoNameIds.ACTION: T.ACTION,
	ProtoNameIds.RESPOND: T.RESPOND,
	ProtoNameIds.COMMANDREQUEST: T.COMMANDREQUEST,
	ProtoNameIds.ERRORINPUT: T.ERRORINPUT,
	ProtoNameIds.HITMSG: T.HITMSG,
	ProtoNameIds.TURNBEGIN: T.TURNBEGIN,
	ProtoNameIds.CARDMSG: T.CARDMSG,
	ProtoNameIds.HURTMSG: T.HURTMSG,
	ProtoNameIds.SKILLMSG: T.SKILLMSG,
}

## 线上协议号 -> 事件号；未登记的原样返回
static func event_of(proto_id: int) -> int:
	return PROTO_TO_EVENT.get(proto_id, proto_id)

## 事件号 -> 线上协议号（发送时用）
static func proto_of(event_type: int) -> int:
	for k in PROTO_TO_EVENT.keys():
		if PROTO_TO_EVENT[k] == event_type:
			return k
	return event_type

## 事件号的名字（日志用）
static func event_name(event_type: int) -> String:
	return ProtoNameIds.name_of(proto_of(event_type))
