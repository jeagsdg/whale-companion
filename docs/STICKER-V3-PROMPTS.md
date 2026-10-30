# 新版常用表情：生成规格与提示词

使用内置 `image_gen` 生成，每个姿态单独一张，不需要 API 密钥。12 张原始透明 PNG 保存在 `packages/desktop-pet/assets/v3-*.png`；运行 `node tools/export-curated-stickers.mjs` 可导出到 `鲸鱼娘表情包/清爽新版`，预览图与原图分开。

角色参考：项目的 `assets/idle.png`；第二组以新生成的 `v3-comfort.png` 继续保持角色一致。参考仅用于角色身份和画风，不是截图或剪贴板背景。

共用提示词：

> Use case: identity-preserve. Create ONE high-quality transparent PNG sticker of the reference whale maid. Preserve long blue hair, big blue eyes, whale fin ears and blue whale tail, navy modest maid dress, white apron, white frill headband and blue bow. Full-body adult chibi mascot centered, about 2.7 heads tall, feet and tail visible, transparent breathing room around silhouette. Clean rounded linework, soft cel shading, simplified lace, expressive face readable at 180px. Genuine alpha transparency. No checkerboard, backdrop, floor shadow, text, panels, logos or second character. Natural two hands.

每张在共用约束后添加的姿态规格：

| 文件 | 姿态提示词 |
|---|---|
| v3-comfort | Warm reassuring smile, kind eyes, arms open offering a small friendly hug, relaxed posture. |
| v3-happy | Natural joyful celebration, closed-eye smile, rosy cheeks, small happy fists near chest, a few golden sparkles. Never smug or sarcastic. |
| v3-calm | Softly closed eyes, peaceful smile, one open hand over chest, other near waist, relaxed shoulders. No props or exaggerated symbols. |
| v3-tired | Sleepy softened eyes, sitting comfortably hugging a pale-blue cushion, modest blanket over knees, feet and tail visible. No despair, coffee or laptop. |
| v3-working | Concentrating on a small navy laptop on her lap, sitting with feet visible, friendly determined smile, hands on keyboard and trackpad. |
| v3-success | Warm small proud smile, thumbs-up with one hand, plain clipboard with one green check mark in the other. Never smug. |
| v3-debug | Inspecting a small blue puzzle piece with a round magnifying glass, inquisitive eyes, thoughtful eyebrows and determined smile. Never panicked or crying. |
| v3-received | Warm open-eyed smile, one hand making a gentle OK gesture near shoulder, other hand over heart. Understood and dependable, not a salute. |
| v3-thanks | Grateful closed-eye smile, slight polite bow, hands gently together near chest. Sincere thank you, not worship. |
| v3-hello | Welcoming wave with one hand, open blue eyes, warm small smile, other hand relaxed at side. |
| v3-decline | Friendly polite refusal, one open hand raised outward, small apologetic smile, relaxed eyes. No anger, crosses or symbols. |
| v3-tea | Seated comfortably holding a pale-blue mug with both hands, gentle closed-eye smile, relaxed shoulders, feet and tail visible. No steam covering face. |

验收：逐张检查角色一致性、姿态语义、手部和透明边缘；导出脚本检查 alpha、实际透明面积及文件完整性。复制功能直接使用这些原始 PNG 字节；预览图上的背景和标题不会混入复制内容。
