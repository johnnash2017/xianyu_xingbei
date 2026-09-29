## 阵营与零散网络枚举 —— 对应 AGrail.Team 与 network\*.cs 里的纯枚举
class_name NetIds
extends RefCounted

## 对应 AGrail.Team（值顺序与 C# 一致：Blue=0, Red=1, Other=2）
enum Team { BLUE, RED, OTHER }

## 对应 network\ROLE_STRATEGY.cs
enum ROLE_STRATEGY {
	ROLE_STRATEGY_RANDOM = 1,
	ROLE_STRATEGY_31 = 2,
	ROLE_STRATEGY_BP = 3,
	ROLE_STRATEGY_CM = 4,
	ROLE_STRATEGY_ANY = 5,
	ROLE_STRATEGY_RANK_SOLO = 6,
	ROLE_STRATEGY_RANK_NORMAL = 7,
	ROLE_STRATEGY_RANK_TEAM = 8,
	ROLE_STRATEGY_ALL = 9,
}

## 对应 network\SEAT_MODE.cs
enum SEAT_MODE {
	SEAT_MODE_RANDOM = 1,
	SEAT_MODE_2COMBO = 2,
	SEAT_MODE_3COMBO = 3,
	SEAT_MODE_INTERLACE = 4,
	SEAT_MODE_RBBRRB = 5,
}

## 对应 network\PollingType.cs
enum PollingType {
	POLLING_FORCE_WAIT = 1,
	POLLING_LEGAL_LEAVE = 2,
	POLLING_MVP = 3,
}

## 对应 network\CM_OPRATION.cs
enum CM_OPRATION {
	CM_NULL = 1,
	CM_RED_BAN = 2,
	CM_RED_IB = 3,
	CM_RED_PICK = 4,
	CM_BLUE_BAN = 5,
	CM_BLUE_IB = 6,
	CM_BLUE_PICK = 7,
}

## 对应 network\BP_OPRATION.cs
enum BP_OPRATION {
	BP_NULL = 1,
	BP_BAN = 2,
	BP_PICK = 3,
	BP_BARCHOSE = 4,
	BP_BARCHOSE2 = 5,
}

## 对应 network\GossipType.cs
enum GossipType { GOSSIP_TALK = 1, GOSSIP_NOTICE = 2 }

## 对应 network\PlayerIdConst.cs
const PLAYER_NONE_ID := 100000

## 对应 AGrail.RoleID（枚举值必须一致，RoleFactory 按它查字符串名）
enum RoleID {
	Blank = 0,
	JianSheng = 1,
	KuangZhan = 2,
	GongNv = 3,
	FengYin = 4,
	AnSha = 5,
	ShengNv = 6,
	TianShi = 7,
	MoDao = 8,
	MoJian = 9,
	ShengQiang = 10,
	YuanSu = 11,
	MaoXian = 12,
	SiLing = 13,
	ZhongCai = 14,
	ShenGuan = 15,
	QiDao = 16,
	XianZhe = 17,
	LingFu = 18,
	JianDi = 19,
	GeDouJia = 20,
	YongZhe = 21,
	LingHun = 22,
	WuNv = 23,
	DieWu = 24,
	NvWuShen = 25,
	MoGong = 26,
	YingLingRenXing = 27,
	HongLian = 28,
	MoQiang = 29,
	MoNv = 30,
	ShiRen = 31,
	JingLing = 32,
	XueSeJianLing = 34,
	YueNv = 35,
	ShouLing = 36,
	spMoDao = 108,
	SkillRunner = 999,
}

## 对应 C# `((RoleID)x).ToString()`
static func role_id_name(v: int) -> String:
	for k in RoleID.keys():
		if RoleID[k] == v:
			return k
	return ""

## 对应 C# `(RoleID)Enum.Parse(typeof(RoleID), roleName)`（找不到返回 Blank）
static func role_id_from_name(role_name: String) -> int:
	if RoleID.has(role_name):
		return RoleID[role_name]
	return RoleID.Blank
