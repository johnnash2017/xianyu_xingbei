shader_type canvas_item;
// 状态图标的「两层描边 + 马赛克」。
// 素材是满幅方形插画（400×400 的图、20×20 的像素图都有，整张没有一个透明像素），
// 图标的外轮廓就是控件边界，所以描边只能画在控件内部 —— 但**不盖住原画**：
//   · 最外一圈分给描边：外层白、白边内侧一圈黑，两层宽度合计 ring_w（占边长的比例）；
//   · 剩下的内侧方框放画面，把整张贴图等比缩进去（不是裁掉），原图像素一个不少，只是变小一点；
//   · 控件自身还是 28×28，所以格子布局、相邻图标之间的间距都不受影响。
// 外白的作用：在暗背景（战斗界面就是深色）上先把图标框出来；内黑的作用：把白框和画面隔开。
// 马赛克只糊画面（按块取平均），两层描边仍然是平滑的方框。
// 注意：Godot 的着色器不允许在 fragment 里用 return，分支只能写成 if / else

uniform vec4 outer_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outer_ratio : hint_range(0.0, 0.5) = 0.05;
uniform vec4 inner_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float inner_ratio : hint_range(0.0, 0.5) = 0.045;
// 马赛克程度：画面每边分成多少块（0 或负数＝关闭）。块数按「缩小后的画面」算，
// 28px 的图标留完描边约 23px：14≈1.6px 一块、9≈2.5px、7≈3.3px，越少越糊
uniform float mosaic_blocks : hint_range(0.0, 128.0) = 0.0;
// 每个色块里的取样密度（N×N 次求平均）。1＝只取块中心一个点，细节多的图会满是噪点；
// 4 基本干净（16 次取样），8 最平滑但每像素 64 次取样、开销大
uniform float mosaic_samples : hint_range(1.0, 8.0) = 4.0;
// 图标在屏幕上的边长（像素）：只用来判断「一个色块占多少屏幕像素」。
// 马赛克块小于 mosaic_min_block_px 时（28px 图标块数 ≥ 19 就属于这种，等于把马赛克关了），
// 不做块内平均 —— 那时根本看不出块，平均只是白白把画面糊掉。
uniform float icon_px : hint_range(8.0, 256.0) = 28.0;
uniform float mosaic_min_block_px : hint_range(0.0, 4.0) = 1.5;

// 节点的 modulate（含父级叠加）。在顶点阶段抓一次 —— 以前是在 fragment 里拿 COLOR 除以
// texture(UV) 反解，但两次采样未必逐像素一致，商就不是常数：原图的边缘会以「细线」的形式
// 漏进马赛克里（看着像留了个原图的影子）。抓顶点色是精确值，没这个问题。
varying vec4 v_modulate;

void vertex() {
	// 画布项的顶点色就是 modulate（贴图是在 fragment 里才乘上去的）
	v_modulate = COLOR;
}

void fragment() {
	// 两层描边一共占掉的宽度：这段让给描边，画面从 ring_w 处开始
	float ring_w = outer_ratio + inner_ratio;
	// 把「描边以内那块方框」映射回整张贴图 —— 画面完整缩进去，不被描边覆盖
	vec2 art_uv = (UV - vec2(ring_w)) / max(1.0 - 2.0 * ring_w, 0.0001);
	vec2 sample_uv = clamp(art_uv, vec2(0.0), vec2(1.0));
	// 马赛克：块够大时做块内 N×N 平均，而不是只取块中心一个点。
	// 只取中心点时，细节多、对比强的花纹（鳞片 / 光点 / 细线）每个块随机采到一亮一暗的像素，
	// 一块亮一块暗地跳，看起来就是一片噪点；块内平均等价于「先缩小再放大」，噪点基本消失。
	// 但块本身不到 1.5 屏幕像素时（28px 图标块数 ≥ 19，等于把马赛克关了），块内平均只会
	// 把画面糊掉、换不来任何块感 —— 这时直接按原 UV 取样，保持原来的清晰度。
	vec4 t0;
	if (mosaic_blocks >= 1.0 && icon_px / mosaic_blocks >= mosaic_min_block_px) {
		float blk = 1.0 / mosaic_blocks;
		vec2 block_center = (floor(sample_uv * mosaic_blocks) + 0.5) * blk;
		float n = clamp(mosaic_samples, 1.0, 8.0);
		vec4 acc = vec4(0.0);
		for (int i = 0; i < 8; i++) {
			if (float(i) >= n) {
				break;
			}
			for (int j = 0; j < 8; j++) {
				if (float(j) >= n) {
					break;
				}
				// 把块摊成 n×n 个格，每格取中心：整块覆盖均匀，不会只吃到边角
				vec2 offset = (vec2(float(i), float(j)) + 0.5) / n - 0.5;
				acc += texture(TEXTURE, clamp(block_center + offset * blk, vec2(0.0), vec2(1.0)));
			}
		}
		t0 = acc / (n * n);
	} else {
		t0 = texture(TEXTURE, sample_uv);
	}
	// 到最近边界（上下左右哪边都算）的距离：0＝贴边，0.5＝正中（描边用原始 UV，不受马赛克影响）
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	// 抗锯齿带宽：0.01 约合 28px 图标上 0.3px，够平滑又不糊
	float aa = 0.01;
	vec3 rgb = t0.rgb * v_modulate.rgb;
	// 内黑：贴着白边内侧那圈
	float inner_mask = 1.0 - smoothstep(ring_w - aa, ring_w + aa, d);
	rgb = mix(rgb, inner_color.rgb, inner_mask * inner_color.a);
	// 外白：最外一圈，最后画，压在内黑外面（两圈的交界处靠 aa 带自然过渡）
	float outer_mask = 1.0 - smoothstep(outer_ratio - aa, outer_ratio + aa, d);
	rgb = mix(rgb, outer_color.rgb, outer_mask * outer_color.a);
	// alpha 用「原始 UV」的那次取样：画面缩进去以后，描边那圈按 clamp 取到的是贴图最外一行像素，
	// 有些素材最外一行是透明的，拿它算 alpha 会让描边整圈消失
	float alpha = texture(TEXTURE, UV).a * v_modulate.a;
	COLOR = vec4(rgb, alpha);
}
