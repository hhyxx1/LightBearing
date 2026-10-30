import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, IdGen } from '../model/Models';
import { TimeUtil } from '../services/TimeUtil';
import { LocationService, LocationResult } from '../services/LocationService';
import { AppDb } from '../repository/AppDb';
import { TopBar, EmptyState, ErrorCard, NoticeBar, NumberField, ListRow, StatusBadge, Dialogs } from '../components/Widgets';

/**
 * S04 机位库：收藏地点、输入坐标、标签、搜索与修改。
 * 全部写库（RDB），重启后可复现。
 */
@Component
export struct LocationsPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State keyword: string = '';
  @State places: Place[] = [];
  @State editingId: string = '';
  @State nameInput: string = '';
  @State latInput: string = '';
  @State lonInput: string = '';
  @State tzInput: string = '';
  @State tagsInput: string = '';
  @State noteInput: string = '';
  @State formOpen: boolean = false;
  @State locating: boolean = false;
  @State hint: string = '';
  @State currentId: string = '';

  aboutToAppear(): void {
    this.loadAll();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadAll(): Promise<void> {
    try {
      this.errorText = '';
      await AppState.bootstrap(this.hostContext());
      await AppState.reloadData();
      this.places = AppState.places;
      this.currentId = AppState.currentPlace === undefined ? '' : AppState.currentPlace.id;
      if (this.tzInput.length === 0) {
        this.tzInput = AppState.effectiveTzId();
      }
      this.ready = true;
    } catch (err) {
      this.errorText = `读取机位失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private async applySearch(): Promise<void> {
    try {
      this.places = await AppDb.searchPlaces(this.keyword);
    } catch (err) {
      this.errorText = `搜索失败：${(err as Error).message}`;
    }
  }

  private openForm(place: Place | undefined): void {
    this.formOpen = true;
    if (place === undefined) {
      this.editingId = '';
      this.nameInput = '';
      this.latInput = '';
      this.lonInput = '';
      this.tagsInput = '';
      this.noteInput = '';
      this.tzInput = AppState.effectiveTzId();
    } else {
      this.editingId = place.id;
      this.nameInput = place.name;
      this.latInput = `${place.latWgs84}`;
      this.lonInput = `${place.lonWgs84}`;
      this.tzInput = place.tzId;
      this.tagsInput = place.tags;
      this.noteInput = place.note;
    }
  }

  private parse(value: string): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? NaN : v;
  }

  private async saveForm(): Promise<void> {
    const lat = this.parse(this.latInput);
    const lon = this.parse(this.lonInput);
    if (this.nameInput.trim().length === 0) {
      this.hint = '请填写机位名称。';
      return;
    }
    if (Number.isNaN(lat) || lat < -90 || lat > 90) {
      this.hint = '纬度必须是 -90 到 90 之间的数字。';
      return;
    }
    if (Number.isNaN(lon) || lon < -180 || lon > 180) {
      this.hint = '经度必须是 -180 到 180 之间的数字。';
      return;
    }
    try {
      let place: Place;
      if (this.editingId.length > 0) {
        const existing = AppState.findPlace(this.editingId);
        place = existing === undefined ? AppState.buildPlace(this.nameInput, lat, lon, this.tzInput, this.tagsInput)
          : existing;
        place.name = this.nameInput;
        place.latWgs84 = lat;
        place.lonWgs84 = lon;
        place.tzId = this.tzInput;
        place.tags = this.tagsInput;
        place.note = this.noteInput;
      } else {
        place = AppState.buildPlace(this.nameInput, lat, lon, this.tzInput, this.tagsInput);
        place.note = this.noteInput;
      }
      await AppState.savePlace(place);
      this.formOpen = false;
      this.hint = '已保存。';
      await this.loadAll();
      Dialogs.toast(this.getUIContext(), '机位已保存到本地');
    } catch (err) {
      this.hint = `保存失败：${(err as Error).message}`;
    }
  }

  private async useLocation(): Promise<void> {
    this.locating = true;
    this.hint = '';
    try {
      const result: LocationResult = await LocationService.locateOnce(this.hostContext());
      if (result.point === undefined) {
        this.hint = result.failure === undefined ? '定位失败。' : result.failure.message;
        return;
      }
      this.latInput = result.point.latWgs84.toFixed(6);
      this.lonInput = result.point.lonWgs84.toFixed(6);
      if (this.nameInput.length === 0) {
        this.nameInput = '当前位置';
      }
      if (this.tzInput.length === 0) {
        this.tzInput = TimeUtil.deviceTimeZoneId();
      }
      this.hint = `已填入定位坐标（精度约 ${Math.round(result.point.accuracyM)} 米），请确认名称后保存。`;
    } catch (err) {
      this.hint = `定位失败：${(err as Error).message}`;
    } finally {
      this.locating = false;
    }
  }

  private setCurrent(place: Place): void {
    AppState.setCurrentPlace(place);
    this.currentId = place.id;
    Dialogs.toast(this.getUIContext(), `当前机位：${place.name}`);
  }

  private confirmDelete(place: Place): void {
    Dialogs.confirm(this.getUIContext(), '删除机位', `确定删除「${place.name}」？已有的拍摄计划不会被删除。`,
      '删除', () => {
        AppState.deletePlace(place.id).then(() => {
          this.loadAll();
          Dialogs.toast(this.getUIContext(), '已删除');
        }).catch((err: Error) => {
          this.hint = `删除失败：${err.message}`;
        });
      });
  }

  @Builder
  formSection() {
    Column({ space: Spacing.M }) {
      Text(this.editingId.length > 0 ? '编辑机位' : '新增机位')
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))

      NumberField({
        label: '名称', unit: '', valueText: this.nameInput, placeholder: '例如 外滩机位',
        onChangeText: (text: string) => {
          this.nameInput = text;
        }
      })
      NumberField({
        label: '纬度 WGS84', unit: '°', valueText: this.latInput, placeholder: '如 31.2372',
        onChangeText: (text: string) => {
          this.latInput = text;
        }
      })
      NumberField({
        label: '经度 WGS84', unit: '°', valueText: this.lonInput, placeholder: '如 121.4900',
        onChangeText: (text: string) => {
          this.lonInput = text;
        }
      })
      NumberField({
        label: '时区 ID', unit: '', valueText: this.tzInput, placeholder: '如 Asia/Shanghai',
        onChangeText: (text: string) => {
          this.tzInput = text;
        }
      })
      Row({ space: Spacing.S }) {
        Button('本机时区')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            this.tzInput = TimeUtil.deviceTimeZoneId();
          })
        Button(this.locating ? '定位中…' : '用当前位置')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .fontSize(FontSize.CAPTION)
          .enabled(!this.locating)
          .onClick(() => {
            this.useLocation();
          })
      }
      .width('100%')

      NumberField({
        label: '标签', unit: '', valueText: this.tagsInput, placeholder: '逗号分隔，如 城市,日落',
        onChangeText: (text: string) => {
          this.tagsInput = text;
        }
      })
      NumberField({
        label: '备注', unit: '', valueText: this.noteInput, placeholder: '机位说明（可选）',
        onChangeText: (text: string) => {
          this.noteInput = text;
        }
      })

      if (this.hint.length > 0) {
        NoticeBar({ text: this.hint })
      }

      Row({ space: Spacing.S }) {
        Button('保存机位')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
          .onClick(() => {
            this.saveForm();
          })
        Button('取消')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            this.formOpen = false;
            this.hint = '';
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

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '机位库', subtitle: '收藏地点、坐标、标签与搜索' })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
              this.loadAll();
            },
            onBack: () => {
              this.onBack();
            }
          })
        } else if (!this.ready) {
          Text('读取中…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted')).padding(Spacing.XXL)
        } else {
          Row({ space: Spacing.S }) {
            TextInput({ text: this.keyword, placeholder: '搜索名称/标签/备注' })
              .layoutWeight(1)
              .height(MIN_TOUCH)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .borderRadius(Radius.BUTTON)
              .onChange((value: string) => {
                this.keyword = value;
              })
              .onSubmit(() => {
                this.applySearch();
              })
            Button('搜索')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .onClick(() => {
                this.applySearch();
              })
          }
          .width('100%')

          if (!this.formOpen) {
            Button('新增机位')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .onClick(() => {
                this.openForm(undefined);
              })
          }

          if (this.formOpen) {
            this.formSection()
          }

          if (this.places.length === 0) {
            EmptyState({
              title: '机位库是空的',
              description: '新增一个机位后，今日光线、太阳轨迹、反向寻光都会使用它的坐标。',
              actionLabel: '新增机位',
              onAction: () => {
                this.openForm(undefined);
              }
            })
          } else {
            Column({ space: Spacing.S }) {
              Row() {
                Text('全部机位')
                  .fontSize(FontSize.BODY_L)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.lb_ink'))
                  .layoutWeight(1)
                StatusBadge({ label: `${this.places.length} 个`, tone: 2 })
              }
              .width('100%')

              ForEach(this.places, (place: Place) => {
                Column({ space: Spacing.S }) {
                  Row({ space: Spacing.S }) {
                    Text(place.name)
                      .fontSize(FontSize.BODY_L)
                      .fontColor($r('app.color.lb_ink'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (place.id === this.currentId) {
                      StatusBadge({ label: '当前', tone: 1 })
                    }
                  }
                  .width('100%')

                  Text(`${place.latWgs84.toFixed(4)}°, ${place.lonWgs84.toFixed(4)}° · ${place.tzId} · ${TimeUtil.offsetLabel(place.tzId, TimeUtil.now())}`)
                    .fontSize(FontSize.CAPTION)
                    .fontColor($r('app.color.lb_muted'))
                  if (place.tags.length > 0) {
                    Text(`标签：${place.tags}`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_accent'))
                  }
                  if (place.note.length > 0) {
                    Text(place.note)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                  }

                  Row({ space: Spacing.S }) {
                    Button('设为当前')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .layoutWeight(1)
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel'))
                      .fontColor($r('app.color.lb_ink'))
                      .fontSize(FontSize.CAPTION)
                      .onClick(() => {
                        this.setCurrent(place);
                      })
                    Button('编辑')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .layoutWeight(1)
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel'))
                      .fontColor($r('app.color.lb_ink'))
                      .fontSize(FontSize.CAPTION)
                      .onClick(() => {
                        this.openForm(place);
                      })
                    Button('删除')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .layoutWeight(1)
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel'))
                      .fontColor($r('app.color.lb_primary'))
                      .fontSize(FontSize.CAPTION)
                      .onClick(() => {
                        this.confirmDelete(place);
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(Spacing.M)
                .backgroundColor($r('app.color.lb_panel2'))
                .borderRadius(Radius.BUTTON)
                .alignItems(HorizontalAlign.Start)
              }, (place: Place) => place.id)
            }
            .width('100%')
            .padding(Spacing.L)
            .backgroundColor($r('app.color.lb_panel'))
            .borderRadius(Radius.CARD)
            .alignItems(HorizontalAlign.Start)
          }

          NoticeBar({
            text: '内部一律使用 WGS84 坐标。中国大陆地图服务若使用 GCJ-02，需要经过官方转换后再叠加显示，本页不做未核实的坐标偏移。'
          })
        }
      }
      .width('100%')
      .padding({ bottom: Spacing.XXXL })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
