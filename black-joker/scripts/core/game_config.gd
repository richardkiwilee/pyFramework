class_name GameConfig
extends RefCounted
## =============================================================================
## GameConfig — 跨场景的对局配置（主菜单填写，牌桌读取）
## =============================================================================

enum Mode { AI, LOCAL, HOST, CLIENT }
enum Observe { TRAINING, HELL }

static var mode: int = Mode.AI
static var difficulty: String = "easy"     # "easy" | "hard"
static var observe: int = Observe.TRAINING # 新手模式（放大镜带解码提示/可开对照表）
static var ip: String = "127.0.0.1"
static var port: int = 9001
