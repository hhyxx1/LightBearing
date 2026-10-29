import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { promptAction } from '@kit.ArkUI';

/** 页头 */
@Component
export struct TopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: Spacing.XS }) {
      Text(this.title)
        .fontSize(FontSize.H1)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_ink'))
        .maxLines(2)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.lb_muted'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: Spacing.L, right: Spacing.L, top: Spacing.M, bottom: Spacing.M })
  }
}

/** 数据卡片容器 */
@Component
export struct SectionCard {
  @Prop cardTitle: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: Spacing.M }) {
      if (this.cardTitle.length > 0) {
        Text(this.cardTitle)
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
      }
      this.content()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
  }
}

/** 状态徽标 */
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
    Text(this.label)
      .fontSize(FontSize.CAPTION)
      .fontColor(this.tint())
      .padding({ left: Spacing.S, right: Spacing.S, top: 3, bottom: 3 })
      .borderRadius(Radius.CHIP)
      .borderWidth(1)
      .borderColor(this.tint())
  }
}

/** 指标卡：数值 + 说明 */
@Component
export struct MetricTile {
  @Prop valueText: string = '--';
  @Prop labelText: string = '';
  @Prop highlight: boolean = false;

  build() {
    Column({ space: Spacing.XS }) {
      Text(this.valueText)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.highlight ? $r('app.color.lb_primary') : $r('app.color.lb_ink'))
        .maxLines(1)
      Text(this.labelText)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .padding(Spacing.M)
    .backgroundColor($r('app.color.lb_panel2'))
    .borderRadius(Radius.BUTTON)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 空态 */
@Component
export struct EmptyState {
  @Prop title: string = '尚无数据';
  @Prop description: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };

  build() {
    Column({ space: Spacing.M }) {
      Text('☀')
        .fontSize(42)
        .fontColor($r('app.color.lb_muted'))
      Text(this.title)
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Text(this.description)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
        .textAlign(TextAlign.Center)
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
          .height(MIN_TOUCH)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding(Spacing.XXL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 错误卡：错误说明 + 重试 */
@Component
export struct ErrorCard {
  @Prop message: string = '';
  @Prop retryLabel: string = '重试';
  onRetry: () => void = () => {
  };
  onBack: () => void = () => {
  };

  build() {
    Column({ space: Spacing.M }) {
      Row({ space: Spacing.S }) {
        Text('⚠')
          .fontSize(FontSize.BODY_L)
          .fontColor($r('app.color.lb_primary'))
        Text('出现问题')
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
      }
      .width('100%')

      Text(this.message)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
        .width('100%')

      Row({ space: Spacing.M }) {
        Button(this.retryLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
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
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .onClick(() => {
            this.onBack();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .alignItems(HorizontalAlign.Start)
  }
}

/** 权限教育门：说明为什么需要，并提供降级入口 */
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
    Column({ space: Spacing.M }) {
      Text(this.title)
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Text(this.reason)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
      Row({ space: Spacing.M }) {
        Button(this.grantLabel)
          .type(ButtonType.Normal)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
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
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .onClick(() => {
            this.onFallback();
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
  }
}

/** 列表行 */
@Component
export struct ListRow {
  @Prop primary: string = '';
  @Prop secondary: string = '';
  @Prop trailing: string = '';
  @Prop actionLabel: string = '查看';
  onTap: () => void = () => {
  };
  onAction: () => void = () => {
  };

  build() {
    Row({ space: Spacing.M }) {
      Column({ space: Spacing.XS }) {
        Text(this.primary)
          .fontSize(FontSize.BODY_L)
          .fontColor($r('app.color.lb_ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.secondary)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
          .maxLines(2)
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
        .backgroundColor($r('app.color.lb_panel2'))
        .fontColor($r('app.color.lb_ink'))
        .fontSize(FontSize.CAPTION)
        .onClick(() => {
          this.onAction();
        })
    }
    .width('100%')
    .padding({ top: Spacing.M, bottom: Spacing.M })
    .alignItems(VerticalAlign.Center)
  }
}

/** 标签输入行（数值） */
@Component
export struct NumberField {
  @Prop label: string = '';
  @Prop unit: string = '';
  @Prop valueText: string = '';
  @Prop placeholder: string = '';
  onChangeText: (text: string) => void = () => {
  };

  build() {
    Row({ space: Spacing.S }) {
      Text(this.label)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
        .width(112)
      TextInput({ text: this.valueText, placeholder: this.placeholder })
        .type(InputType.Normal)
        .layoutWeight(1)
        .height(MIN_TOUCH)
        .backgroundColor($r('app.color.lb_panel2'))
        .fontColor($r('app.color.lb_ink'))
        .borderRadius(Radius.BUTTON)
        .onChange((value: string) => {
          this.onChangeText(value);
        })
      if (this.unit.length > 0) {
        Text(this.unit)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
          .width(28)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/** 开关行 */
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
        .onChange((on: boolean) => {
          this.onToggle(on);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: MIN_TOUCH })
    .alignItems(VerticalAlign.Center)
    .padding({ top: Spacing.S, bottom: Spacing.S })
  }
}

/** 提示条（用于「数据是本地计算」等诚实标注） */
@Component
export struct NoticeBar {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(FontSize.CAPTION)
      .fontColor($r('app.color.lb_muted'))
      .width('100%')
      .padding(Spacing.M)
      .backgroundColor($r('app.color.lb_panel2'))
      .borderRadius(Radius.BUTTON)
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
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
    }
    .width('100%')
    .padding(Spacing.XXL)
    .alignItems(HorizontalAlign.Center)
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
