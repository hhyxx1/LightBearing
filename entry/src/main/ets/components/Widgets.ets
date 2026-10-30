import {
  FontSize, Radius, Spacing, MIN_TOUCH, NAV_CAPTION_SIZE, NAV_CAPTION_SPACING, EYEBROW_SPACING
} from '../common/Theme';
import { promptAction } from '@kit.ArkUI';

/**
 * 可复用组件 —— 视觉严格对齐设计稿 lightbearing_ui.html：
 * .eyebrow / .pagetitle / .subtitle / .hero / .card / .chip / .stat /
 * .listitem / .iconbox / .field / .toggle / .helpmeta / .btn(.primary|.ghost)
 */

/** 页头：eyebrow + 标题 + 副标题（对应 .eyebrow + .pagetitle + .subtitle） */
@Component
export struct TopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop eyebrowText: string = 'LIGHTBEARING · API 26';
  @Prop chipText: string = '';

  build() {
    Column({ space: Spacing.S }) {
      Row({ space: Spacing.M }) {
        Text(this.eyebrowText)
          .fontSize(FontSize.EYEBROW)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(EYEBROW_SPACING)
          .fontColor($r('app.color.lb_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.chipText.length > 0) {
          Text(`•  ${this.chipText}`)
            .fontSize(FontSize.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_primary'))
            .padding({ left: Spacing.M, right: Spacing.M, top: 5, bottom: 5 })
            .borderRadius(Radius.CHIP)
            .backgroundColor($r('app.color.lb_chip_bg'))
            .borderWidth(1)
            .borderColor($r('app.color.lb_chip_border'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.title)
        .fontSize(FontSize.H1)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_ink'))
        .width('100%')
        .maxLines(2)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(FontSize.BODY_L)
          .fontColor($r('app.color.lb_muted'))
          .lineHeight(24)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: Spacing.XL, right: Spacing.XL, top: Spacing.XL, bottom: Spacing.L })
  }
}

/** 顶部主视觉（对应 .hero：125° 渐变 + 右上装饰环） */
@Component
export struct HeroCard {
  @Prop heroTitle: string = '';
  @Prop heroBody: string = '';
  @Prop primaryLabel: string = '';
  @Prop ghostLabel: string = '';

  onPrimary: () => void = () => {
  };
  onGhost: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 装饰环（对应 .hero:after：35px 粗描边圆环，只从右上角探出，溢出裁切）
      Circle()
        .width(220)
        .height(220)
        .fill(Color.Transparent)
        .stroke($r('app.color.lb_hero_glow'))
        .strokeWidth(35)
        .translate({ x: 128, y: -150 })

      Column({ space: Spacing.S }) {
        Text(heroEyebrow())
          .fontSize(FontSize.EYEBROW)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(EYEBROW_SPACING)
          .fontColor($r('app.color.lb_primary'))
        Text(this.heroTitle)
          .fontSize(FontSize.HERO_H2)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .width('100%')
        Text(this.heroBody)
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.lb_muted'))
          .lineHeight(23)
          .width('100%')
        if (this.primaryLabel.length > 0 || this.ghostLabel.length > 0) {
          Row({ space: Spacing.M }) {
            if (this.primaryLabel.length > 0) {
              Button(this.primaryLabel)
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_primary'))
                .fontColor($r('app.color.lb_on_primary'))
                .fontSize(FontSize.BODY)
                .fontWeight(FontWeight.Bold)
                .padding({ left: Spacing.L, right: Spacing.L })
                .onClick(() => {
                  this.onPrimary();
                })
            }
            if (this.ghostLabel.length > 0) {
              Button(this.ghostLabel)
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .borderRadius(Radius.BUTTON)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.lb_ink'))
                .fontSize(FontSize.BODY)
                .fontWeight(FontWeight.Bold)
                .borderWidth(1)
                .borderColor($r('app.color.lb_line'))
                .padding({ left: Spacing.L, right: Spacing.L })
                .onClick(() => {
                  this.onGhost();
                })
            }
          }
          .width('100%')
          .margin({ top: Spacing.S })
          .justifyContent(FlexAlign.Start)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Spacing.XXL, right: Spacing.XXL, top: Spacing.XXL, bottom: Spacing.XXL })
      .width('100%')
    }
    .width('100%')
    .borderRadius(Radius.HERO)
    .backgroundColor($r('app.color.lb_panel'))
    .linearGradient({
      angle: 125,
      colors: [[$r('app.color.lb_hero_glow'), 0.0], [$r('app.color.lb_panel'), 1.0]]
    })
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .clip(true)
  }
}

/** 该文案与设计稿 .hero .eyebrow 一致，并与页头 eyebrow 保持同一口径 */
function heroEyebrow(): string {
  return 'LIGHTBEARING · API 26';
}

/** 数据卡片（对应 .card：圆角 19，panel 底，1px 线框，padding 20） */
@Component
export struct SectionCard {
  @Prop cardTitle: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: Spacing.L }) {
      if (this.cardTitle.length > 0) {
        Text(this.cardTitle)
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .width('100%')
      }
      this.content()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
  }
}

/** 指标卡（对应 .stat：数值 24，标签 11 muted） */
@Component
export struct MetricTile {
  @Prop valueText: string = '--';
  @Prop labelText: string = '';
  @Prop highlight: boolean = false;

  build() {
    Column({ space: Spacing.S }) {
      Text(this.valueText)
        .fontSize(FontSize.STAT)
        .maxFontSize(FontSize.STAT)
        .minFontSize(12)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MAX_LINES_FIRST)
        .fontWeight(FontWeight.Bolder)
        .fontColor(this.highlight ? $r('app.color.lb_primary') : $r('app.color.lb_ink'))
        .fontFeature('"tnum" 1')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.labelText)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
        .maxLines(2)
        .textAlign(TextAlign.Start)
    }
    .layoutWeight(1)
    .padding({ left: Spacing.L, right: Spacing.L, top: Spacing.L, bottom: Spacing.L })
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.STAT)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }
}

/** 状态芯片（对应 .chip：主色 35% 描边 + 10% 底 + 40 圆角） */
@Component
export struct StatusBadge {
  @Prop label: string = '';
  @Prop tone: number = 0;

  private tint(): Resource {
    if (this.tone === 1) {
      return $r('app.color.lb_primary');
    }
    if (this.tone === 2) {
      return $r('app.color.lb_accent');
    }
    return $r('app.color.lb_muted');
  }

  build() {
    Row({ space: 6 }) {
      Text('•')
        .fontSize(FontSize.CAPTION)
        .fontColor(this.tint())
      Text(this.label)
        .fontSize(FontSize.CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tint())
    }
    .padding({ left: Spacing.M, right: Spacing.M, top: 5, bottom: 5 })
    .borderRadius(Radius.CHIP)
    .backgroundColor($r('app.color.lb_chip_bg'))
    .borderWidth(1)
    .borderColor($r('app.color.lb_chip_border'))
    .alignItems(VerticalAlign.Center)
  }
}

/** 图标容器（对应 .iconbox：40×40，主色 15% 底，圆角 12） */
@Component
export struct IconBox {
  @Prop boxSize: number = 40;
  src: Resource = $r('app.media.ic_sun_primary');

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.src)
        .width(this.boxSize * 0.48)
        .height(this.boxSize * 0.48)
        .objectFit(ImageFit.Contain)
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .backgroundColor($r('app.color.lb_iconbox_bg'))
    .borderRadius(Radius.ICONBOX)
  }
}

/** 空态：图标 + 标题 + 说明 + 主按钮 */
@Component
export struct EmptyState {
  @Prop title: string = '尚无数据';
  @Prop description: string = '';
  @Prop actionLabel: string = '';
  iconSrc: Resource = $r('app.media.ic_sun_primary');
  onAction: () => void = () => {
  };

  build() {
    Column({ space: Spacing.L }) {
      IconBox({ boxSize: 56, src: this.iconSrc })
      Text(this.title)
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Text(this.description)
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_muted'))
        .textAlign(TextAlign.Center)
        .lineHeight(21)
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_on_primary'))
          .fontWeight(FontWeight.Bold)
          .fontSize(FontSize.BODY)
          .height(MIN_TOUCH)
          .padding({ left: Spacing.XL, right: Spacing.XL })
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding(Spacing.XXL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Center)
  }
}

/** 错误卡：警告图标 + 说明 + 重试/返回 */
@Component
export struct ErrorCard {
  @Prop message: string = '';
  @Prop retryLabel: string = '重试';
  onRetry: () => void = () => {
  };
  onBack: () => void = () => {
  };

  build() {
    Column({ space: Spacing.L }) {
      Row({ space: Spacing.M }) {
        IconBox({ boxSize: 36, src: $r('app.media.ic_warning_primary') })
        Text('出现问题')
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.message)
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_muted'))
        .lineHeight(21)
        .width('100%')

      Row({ space: Spacing.M }) {
        Button(this.retryLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_on_primary'))
          .fontWeight(FontWeight.Bold)
          .fontSize(FontSize.BODY)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .onClick(() => {
            this.onRetry();
          })
        Button('返回')
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .fontWeight(FontWeight.Bold)
          .fontSize(FontSize.BODY)
          .height(MIN_TOUCH)
          .borderWidth(1)
          .borderColor($r('app.color.lb_line'))
          .layoutWeight(1)
          .onClick(() => {
            this.onBack();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }
}

/** 权限教育门 */
@Component
export struct PermissionGate {
  @Prop title: string = '需要权限';
  @Prop reason: string = '';
  @Prop grantLabel: string = '授予权限';
  @Prop fallbackLabel: string = '改用手动方式';
  onGrant: () => void = () => {
  };
  onFallback: () => void = () => {
  };

  build() {
    Column({ space: Spacing.L }) {
      Row({ space: Spacing.M }) {
        IconBox({ boxSize: 36, src: $r('app.media.ic_location_current_primary') })
        Text(this.title)
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.reason)
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_muted'))
        .lineHeight(21)

      Row({ space: Spacing.M }) {
        Button(this.grantLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_on_primary'))
          .fontWeight(FontWeight.Bold)
          .fontSize(FontSize.BODY)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .onClick(() => {
            this.onGrant();
          })
        Button(this.fallbackLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .fontWeight(FontWeight.Bold)
          .fontSize(FontSize.BODY)
          .height(MIN_TOUCH)
          .borderWidth(1)
          .borderColor($r('app.color.lb_line'))
          .layoutWeight(1)
          .onClick(() => {
            this.onFallback();
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
  }
}

/** 列表行（对应 .listitem：iconbox + 主/次文案 + ghost 按钮） */
@Component
export struct ListRow {
  @Prop primary: string = '';
  @Prop secondary: string = '';
  @Prop trailing: string = '';
  @Prop actionLabel: string = '查看';
  iconSrc: Resource = $r('app.media.ic_note_primary');
  onTap: () => void = () => {
  };
  onAction: () => void = () => {
  };

  build() {
    Row({ space: Spacing.M }) {
      IconBox({ boxSize: 40, src: this.iconSrc })
      Column({ space: Spacing.XS }) {
        Text(this.primary)
          .fontSize(FontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.secondary.length > 0) {
          Text(this.secondary)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
            .maxLines(2)
        }
        if (this.trailing.length > 0) {
          Text(this.trailing)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_accent'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.onTap();
      })

      Button(this.actionLabel)
        .type(ButtonType.Normal)
        .height(MIN_TOUCH)
        .borderRadius(Radius.BUTTON)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor($r('app.color.lb_line'))
        .fontColor($r('app.color.lb_ink'))
        .fontSize(FontSize.SMALL)
        .fontWeight(FontWeight.Bold)
        .onClick(() => {
          this.onAction();
        })
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel2'))
    .borderRadius(Radius.BUTTON)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(VerticalAlign.Center)
  }
}

/** 数值/文本输入（对应 .field：标签在上，输入 panel2 + 线框，圆角 11） */
@Component
export struct NumberField {
  @Prop label: string = '';
  @Prop unit: string = '';
  @Prop valueText: string = '';
  @Prop placeholder: string = '';
  onChangeText: (text: string) => void = () => {
  };

  build() {
    Column({ space: Spacing.S }) {
      Row() {
        Text(this.label)
          .fontSize(FontSize.SMALL)
          .fontColor($r('app.color.lb_muted'))
          .layoutWeight(1)
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
      }
      .width('100%')

      TextInput({ text: this.valueText, placeholder: this.placeholder })
        .type(InputType.Normal)
        .width('100%')
        .height(MIN_TOUCH)
        .backgroundColor($r('app.color.lb_panel2'))
        .fontColor($r('app.color.lb_ink'))
        .placeholderColor($r('app.color.lb_muted'))
        .fontSize(FontSize.BODY)
        .borderRadius(Radius.BUTTON)
        .borderWidth(1)
        .borderColor($r('app.color.lb_line'))
        .accessibilityText(this.label)
        .onChange((value: string) => {
          this.onChangeText(value);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 开关行（对应 .toggle：上下 12 间距 + 底线） */
@Component
export struct SwitchRow {
  @Prop label: string = '';
  @Prop description: string = '';
  @Prop isOn: boolean = false;
  onToggle: (on: boolean) => void = () => {
  };

  build() {
    Row({ space: Spacing.M }) {
      Column({ space: Spacing.XS }) {
        Text(this.label)
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.lb_ink'))
        if (this.description.length > 0) {
          Text(this.description)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor($r('app.color.lb_primary'))
        .accessibilityText(this.label)
        .onChange((on: boolean) => {
          this.onToggle(on);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: MIN_TOUCH })
    .alignItems(VerticalAlign.Center)
    .padding({ top: Spacing.M, bottom: Spacing.M })
    .border({ width: { bottom: 1 }, color: $r('app.color.lb_line') })
  }
}

/** 提示条（对应 .helpmeta：左侧 2px 主色条 + 主色 6% 底） */
@Component
export struct NoticeBar {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(FontSize.SMALL)
      .fontColor($r('app.color.lb_muted'))
      .lineHeight(21)
      .width('100%')
      .padding({ left: Spacing.M, right: Spacing.M, top: Spacing.M, bottom: Spacing.M })
      .backgroundColor($r('app.color.lb_chip_bg'))
      .borderRadius(6)
      .border({ width: { left: 2 }, color: $r('app.color.lb_primary') })
  }
}

/** 骨架屏占位条（任务书要求 Loading 态必须有骨架屏，而不是只有转圈） */
@Component
export struct SkeletonBar {
  @Prop barWidth: string = '100%';
  @Prop barHeight: number = 14;

  build() {
    Row()
      .width(this.barWidth)
      .height(this.barHeight)
      .backgroundColor($r('app.color.lb_panel2'))
      .borderRadius(6)
  }
}

/** 骨架屏卡片：标题条 + 三条内容条，模拟真实卡片密度 */
@Component
export struct SkeletonCard {
  build() {
    Column({ space: Spacing.M }) {
      SkeletonBar({ barWidth: '38%', barHeight: 18 })
      SkeletonBar({ barWidth: '100%' })
      SkeletonBar({ barWidth: '86%' })
      SkeletonBar({ barWidth: '64%' })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
  }
}

/** 加载中 */
@Component
export struct LoadingBlock {
  @Prop label: string = '计算中';

  build() {
    Column({ space: Spacing.M }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.lb_primary'))
      Text(this.label)
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_muted'))
    }
    .width('100%')
    .padding(Spacing.XXL)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 导航项标题（对应 .navcaption：10px 大写 字距 2 bold muted） */
@Component
export struct NavCaption {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(NAV_CAPTION_SIZE)
      .fontWeight(FontWeight.Bold)
      .letterSpacing(NAV_CAPTION_SPACING)
      .fontColor($r('app.color.lb_muted'))
      .width('100%')
      .padding({ left: Spacing.M, right: Spacing.M, top: Spacing.M, bottom: Spacing.M })
  }
}

/** 分隔线（对应 .separator） */
@Component
export struct DividerLine {
  build() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.lb_line'))
  }
}

/** 工具按钮（任务书 §3 的 ToolButton）：紧凑的图标＋文字按钮，用于页面工具条 */
@Component
export struct ToolButton {
  @Prop label: string = '';
  @Prop compact: boolean = false;
  /** true=主色实心；false=描边 ghost */
  @Prop emphasized: boolean = false;
  iconSrc: Resource = $r('app.media.ic_plus_primary');
  onTap: () => void = () => {
  };

  build() {
    Row({ space: Spacing.S }) {
      Image(this.iconSrc)
        .width(this.compact ? 16 : 18)
        .height(this.compact ? 16 : 18)
        .objectFit(ImageFit.Contain)
      Text(this.label)
        .fontSize(this.compact ? FontSize.SMALL : FontSize.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.emphasized ? $r('app.color.lb_on_primary') : $r('app.color.lb_ink'))
    }
    .padding({ left: this.compact ? Spacing.M : Spacing.L, right: this.compact ? Spacing.M : Spacing.L })
    .height(this.compact ? 34 : MIN_TOUCH)
    .borderRadius(Radius.BUTTON)
    .backgroundColor(this.emphasized ? $r('app.color.lb_primary') : Color.Transparent)
    .borderWidth(this.emphasized ? 0 : 1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
    .accessibilityText(this.label)
  }
}

/** 分段选择器（任务书 §3 的 SegmentedPicker）：设置页主题/角度单位等通用 */
@Component
export struct SegmentedPicker {
  @Prop segments: string[] = [];
  @Prop selectedIndex: number = 0;
  /** 小号样式，用于卡片内的紧凑分段 */
  @Prop compact: boolean = false;
  onSelect: (index: number) => void = () => {
  };

  build() {
    Row({ space: Spacing.S }) {
      ForEach(this.segments, (label: string, index: number) => {
        Text(label)
          .fontSize(this.compact ? FontSize.CAPTION : FontSize.BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(index === this.selectedIndex
            ? $r('app.color.lb_on_primary') : $r('app.color.lb_ink'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(this.compact ? 34 : MIN_TOUCH)
          .borderRadius(Radius.BUTTON)
          .backgroundColor(index === this.selectedIndex
            ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
          .onClick(() => {
            this.onSelect(index);
          })
          .accessibilityText(label)
      }, (label: string, index: number) => `${label}_${index}`)
    }
    .width('100%')
  }
}

/** 计划/机位磁贴（任务书 §3 的 ProjectTile）：列表卡片的统一外观 */
@Component
export struct ProjectTile {
  @Prop primary: string = '';
  @Prop secondary: string = '';
  @Prop meta: string = '';
  @Prop statusText: string = '';
  @Prop statusTone: number = 0;
  iconSrc: Resource = $r('app.media.ic_planner_primary');
  onTap: () => void = () => {
  };

  build() {
    Row({ space: Spacing.M }) {
      IconBox({ boxSize: 40, src: this.iconSrc })
      Column({ space: Spacing.XS }) {
        Row({ space: Spacing.S }) {
          Text(this.primary)
            .fontSize(FontSize.BODY_L)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.lb_ink'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.statusText.length > 0) {
            StatusBadge({ label: this.statusText, tone: this.statusTone })
          }
        }
        .width('100%')

        if (this.secondary.length > 0) {
          Text(this.secondary)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
            .maxLines(2)
        }
        if (this.meta.length > 0) {
          Text(this.meta)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_accent'))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_muted'))
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel2'))
    .borderRadius(Radius.BUTTON)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
    .accessibilityText(`${this.primary} ${this.secondary}`)
  }
}

/** 进度浮层（任务书 §3 的 ProgressSheet）：长耗时任务的真实进度与取消 */
@Component
export struct ProgressSheet {
  @Prop visible: boolean = false;
  @Prop sheetTitle: string = '正在计算';
  @Prop detail: string = '';
  @Prop percent: number = 0;
  @Prop cancellable: boolean = true;
  onCancel: () => void = () => {
  };

  build() {
    if (this.visible) {
      Column() {
        Column({ space: Spacing.M }) {
          Text(this.sheetTitle)
            .fontSize(FontSize.BODY_L)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.lb_ink'))
            .width('100%')
          Progress({ value: this.percent, total: 100, type: ProgressType.Linear })
            .color($r('app.color.lb_primary'))
            .backgroundColor($r('app.color.lb_panel2'))
            .width('100%')
          Row() {
            Text(this.detail)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
              .layoutWeight(1)
            Text(`${Math.round(this.percent)}%`)
              .fontSize(FontSize.CAPTION)
              .fontFeature('"tnum" 1')
              .fontColor($r('app.color.lb_primary'))
          }
          .width('100%')
          if (this.cancellable) {
            Button('取消任务')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .fontWeight(FontWeight.Bold)
              .borderWidth(1)
              .borderColor($r('app.color.lb_line'))
              .onClick(() => {
                this.onCancel();
              })
          }
        }
        .width('100%')
        .padding(Spacing.XL)
        .backgroundColor($r('app.color.lb_panel'))
        .borderRadius({ topLeft: Radius.HERO, topRight: Radius.HERO })
        .borderWidth(1)
        .borderColor($r('app.color.lb_line'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .backgroundColor('#99060C14')
    }
  }
}

/** 键盘快捷键提示（任务书 §3 的 KeyboardShortcutHint）：仅在检测到物理键盘时显示 */
@Component
export struct KeyboardShortcutHint {
  @Prop keys: string[] = [];
  @Prop description: string = '';

  build() {
    Row({ space: Spacing.S }) {
      ForEach(this.keys, (key: string) => {
        Text(key)
          .fontSize(FontSize.CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.lb_ink'))
          .fontFeature('"tnum" 1')
          .padding({ left: Spacing.S, right: Spacing.S, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.lb_panel2'))
          .borderRadius(6)
          .borderWidth(1)
          .borderColor($r('app.color.lb_line'))
      }, (key: string) => key)
      Text(this.description)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: Spacing.S, bottom: Spacing.S })
  }
}

/** 对话框与 toast 的统一入口（使用 UIContext，避免废弃全局 promptAction） */
export class Dialogs {
  static toast(ui: UIContext, message: string): void {
    const options: promptAction.ShowToastOptions = {
      message: message,
      duration: 2200
    };
    ui.getPromptAction().showToast(options);
  }

  static confirm(ui: UIContext, title: string, message: string, confirmText: string,
    onConfirm: () => void, onCancel?: () => void): void {
    const button: promptAction.Button = {
      text: confirmText,
      color: '#FFBC6B'
    };
    const cancelButton: promptAction.Button = {
      text: '取消',
      color: '#A2B9C5'
    };
    const options: promptAction.ShowDialogOptions = {
      title: title,
      message: message,
      buttons: [cancelButton, button]
    };
    ui.getPromptAction().showDialog(options)
      .then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          onConfirm();
        } else if (onCancel !== undefined) {
          onCancel();
        }
      })
      .catch(() => {
        if (onCancel !== undefined) {
          onCancel();
        }
      });
  }
}
