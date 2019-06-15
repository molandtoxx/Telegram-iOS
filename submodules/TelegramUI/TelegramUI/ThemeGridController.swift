import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LegacyComponents
import TelegramPresentationData
import TelegramUIPreferences

final class ThemeGridController: ViewController {
    private var controllerNode: ThemeGridControllerNode {
        return self.displayNode as! ThemeGridControllerNode
    }
    
    private let _ready = Promise<Bool>()
    override var ready: Promise<Bool> {
        return self._ready
    }
    
    private let context: AccountContext
    
    private var presentationData: PresentationData
    private let presentationDataPromise = Promise<PresentationData>()
    private var presentationDataDisposable: Disposable?
    
    private var searchContentNode: NavigationBarSearchContentNode?
    
    private var isEmpty: Bool?
    private var editingMode: Bool = false
    
    private var validLayout: ContainerViewLayout?
    
    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationDataPromise.set(.single(self.presentationData))
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.title = self.presentationData.strings.Wallpaper_Title
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        
        self.scrollToTop = { [weak self] in
            if let strongSelf = self {
                if let searchContentNode = strongSelf.searchContentNode {
                    searchContentNode.updateExpansionProgress(1.0, animated: true)
                }
                strongSelf.controllerNode.scrollToTop()
            }
        }
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                
                strongSelf.presentationData = presentationData
                strongSelf.presentationDataPromise.set(.single(presentationData))
                
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings()
                }
            }
        })
        
        self.searchContentNode = NavigationBarSearchContentNode(theme: self.presentationData.theme, placeholder: self.presentationData.strings.Wallpaper_Search, activate: { [weak self] in
            self?.activateSearch()
        })
        self.navigationBar?.setContentNode(self.searchContentNode, animated: false)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
    }
    
    private func updateThemeAndStrings() {
        self.title = self.presentationData.strings.Wallpaper_Title
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        
        if let isEmpty = self.isEmpty, isEmpty {
        } else {
            if self.editingMode {
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
            } else {
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
            }
        }
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData))
        self.searchContentNode?.updateThemeAndPlaceholder(theme: self.presentationData.theme, placeholder: self.presentationData.strings.Wallpaper_Search)
        
        if self.isNodeLoaded {
            self.controllerNode.updatePresentationData(self.presentationData)
        }
    }
    
    override func loadDisplayNode() {
        self.displayNode = ThemeGridControllerNode(context: self.context, presentationData: self.presentationData, presentPreviewController: { [weak self] source in
            if let strongSelf = self {
                let controller = WallpaperGalleryController(context: strongSelf.context, source: source)
                controller.apply = { [weak self, weak controller] wallpaper, mode, cropRect in
                    if let strongSelf = self {
                        uploadCustomWallpaper(context: strongSelf.context, wallpaper: wallpaper, mode: mode, cropRect: cropRect, completion: { [weak self, weak controller] in
                            if let strongSelf = self {
                                strongSelf.deactivateSearch(animated: false)
                                strongSelf.controllerNode.scrollToTop(animated: false)
                            }
                            if let controller = controller {
                                switch wallpaper {
                                    case .asset, .contextResult:
                                        controller.dismiss(forceAway: true)
                                    default:
                                        break
                                }
                            }
                        })
                    }
                }
                self?.present(controller, in: .window(.root), with: nil, blockInteraction: true)
            }
        }, presentGallery: { [weak self] in
            if let strongSelf = self {
                presentCustomWallpaperPicker(context: strongSelf.context, present: { [weak self] controller in
                    self?.present(controller, in: .window(.root), with: nil, blockInteraction: true)
                })
            }
        }, presentColors: { [weak self] in
            if let strongSelf = self {
                let controller = ThemeColorsGridController(context: strongSelf.context)
                (strongSelf.navigationController as? NavigationController)?.pushViewController(controller)
            }
        }, emptyStateUpdated: { [weak self] empty in
            if let strongSelf = self {
                if empty != strongSelf.isEmpty {
                    strongSelf.isEmpty = empty
                    
                    if empty {
                        strongSelf.navigationItem.setRightBarButton(nil, animated: true)
                    } else {
                        if strongSelf.editingMode {
                            strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Done, style: .done, target: strongSelf, action: #selector(strongSelf.donePressed))
                        } else {
                            strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Edit, style: .plain, target: strongSelf, action: #selector(strongSelf.editPressed))
                        }
                    }
                }
            }
        }, deleteWallpapers: { [weak self] wallpapers, completed in
            if let strongSelf = self {
                let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                var items: [ActionSheetItem] = []
                items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Wallpaper_DeleteConfirmation(Int32(wallpapers.count)), color: .destructive, action: { [weak self, weak actionSheet] in
   
                    actionSheet?.dismissAnimated()
                    completed()
                    
                    guard let strongSelf = self else {
                        return
                    }
                    for wallpaper in wallpapers {
                        if wallpaper == strongSelf.presentationData.chatWallpaper {
                            let _ = (updatePresentationThemeSettingsInteractively(accountManager: strongSelf.context.sharedContext.accountManager, { current in
                                var fallbackWallpaper: TelegramWallpaper = .builtin(WallpaperSettings())
                                if case let .builtin(theme) = current.theme {
                                    switch theme {
                                        case .day:
                                            fallbackWallpaper = .color(0xffffff)
                                        case .nightGrayscale:
                                            fallbackWallpaper = .color(0x000000)
                                        case .nightAccent:
                                            fallbackWallpaper = .color(0x18222d)
                                        default:
                                            fallbackWallpaper = .builtin(WallpaperSettings())
                                    }
                                }
                                
                                var themeSpecificChatWallpapers = current.themeSpecificChatWallpapers
                                themeSpecificChatWallpapers[current.theme.index] = fallbackWallpaper
                                return PresentationThemeSettings(chatWallpaper: fallbackWallpaper, theme: current.theme, themeAccentColor: current.themeAccentColor, themeSpecificChatWallpapers: themeSpecificChatWallpapers, fontSize: current.fontSize, automaticThemeSwitchSetting: current.automaticThemeSwitchSetting, largeEmoji: current.largeEmoji, disableAnimations: current.disableAnimations)
                            })).start()
                            break
                        }
                    }
                    
                    var deleteWallpapers: [Signal<Void, NoError>] = []
                    for wallpaper in wallpapers {
                        deleteWallpapers.append(deleteWallpaper(account: strongSelf.context.account, wallpaper: wallpaper))
                    }
                    
                    let _ = (combineLatest(deleteWallpapers)
                    |> deliverOnMainQueue).start(completed: { [weak self] in
                        if let strongSelf = self {
                            strongSelf.controllerNode.updateWallpapers()
                        }
                    })
                    
                    strongSelf.donePressed()
                }))
                
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: items),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                strongSelf.present(actionSheet, in: .window(.root))
            }
        }, shareWallpapers: { [weak self] wallpapers in
            if let strongSelf = self {
                strongSelf.shareWallpapers(wallpapers)
            }
        }, resetWallpapers: { [weak self] in
            if let strongSelf = self {
                let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                let items: [ActionSheetItem] = [
                    ActionSheetButtonItem(title: strongSelf.presentationData.strings.Wallpaper_ResetWallpapersConfirmation, color: .destructive, action: { [weak self, weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        
                        if let strongSelf = self {
                            strongSelf.scrollToTop?()
                            
                            let controller = OverlayStatusController(theme: strongSelf.presentationData.theme, strings: strongSelf.presentationData.strings, type: .loading(cancelled: nil))
                            strongSelf.present(controller, in: .window(.root))
                            
                            let _ = resetWallpapers(account: strongSelf.context.account).start(completed: { [weak self, weak controller] in
                                let _ = (strongSelf.context.sharedContext.accountManager.transaction { transaction -> Void in
                                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.presentationThemeSettings, { entry in
                                        let current: PresentationThemeSettings
                                        if let entry = entry as? PresentationThemeSettings {
                                            current = entry
                                        } else {
                                            current = PresentationThemeSettings.defaultSettings
                                        }
                                        let wallpaper: TelegramWallpaper
                                        if case let .builtin(theme) = current.theme {
                                            switch theme {
                                                case .day:
                                                    wallpaper = .color(0xffffff)
                                                case .nightGrayscale:
                                                    wallpaper = .color(0x000000)
                                                case .nightAccent:
                                                    wallpaper = .color(0x18222d)
                                                default:
                                                    wallpaper = .builtin(WallpaperSettings())
                                            }
                                        } else {
                                            wallpaper = .builtin(WallpaperSettings())
                                        }
                                        return PresentationThemeSettings(chatWallpaper: wallpaper, theme: current.theme, themeAccentColor: current.themeAccentColor, themeSpecificChatWallpapers: [:], fontSize: current.fontSize, automaticThemeSwitchSetting: current.automaticThemeSwitchSetting, largeEmoji: current.largeEmoji, disableAnimations: current.disableAnimations)
                                    })
                                }).start()
                                
                                let _ = (telegramWallpapers(postbox: strongSelf.context.account.postbox, network: strongSelf.context.account.network)
                                |> deliverOnMainQueue).start(completed: { [weak self, weak controller] in
                                    controller?.dismiss()
                                    if let strongSelf = self {
                                        strongSelf.controllerNode.updateWallpapers()
                                    }
                                })
                            })
                        }
                    })
                ]
                actionSheet.setItemGroups([ActionSheetItemGroup(items: items),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                strongSelf.present(actionSheet, in: .window(.root))
            }
        }, popViewController: { [weak self] in
            if let strongSelf = self {
                let _ = (strongSelf.navigationController as? NavigationController)?.popViewController(animated: true)
            }
        })
        self.controllerNode.navigationBar = self.navigationBar
        self.controllerNode.requestDeactivateSearch = { [weak self] in
            self?.deactivateSearch(animated: true)
        }
        
        self.controllerNode.gridNode.visibleContentOffsetChanged = { [weak self] offset in
            if let strongSelf = self, let searchContentNode = strongSelf.searchContentNode {
                searchContentNode.updateGridVisibleContentOffset(offset)
            }
        }

        self.controllerNode.gridNode.scrollingCompleted = { [weak self] in
            if let strongSelf = self, let searchContentNode = strongSelf.searchContentNode {
                let _ = strongSelf.controllerNode.fixNavigationSearchableGridNodeScrolling(searchNode: searchContentNode)
            }
        }
        
        self._ready.set(self.controllerNode.ready.get())
        
        self.displayNodeDidLoad()
    }
    
    private func shareWallpapers(_ wallpapers: [TelegramWallpaper]) {
        var string: String = ""
        for wallpaper in wallpapers {
            var item: String?
            switch wallpaper {
                case let .file(_, _, _, _, isPattern, _, slug, _, settings):
                    var options: [String] = []
                    if isPattern {
                        if let color = settings.color {
                            options.append("bg_color=\(UIColor(rgb: UInt32(bitPattern: color)).hexString)")
                        }
                        if let intensity = settings.intensity {
                            options.append("intensity=\(intensity)")
                        }
                    }
                    
                    var optionsString = ""
                    if !options.isEmpty {
                        optionsString = "?\(options.joined(separator: "&"))"
                    }
                    item = slug + optionsString
                case let .color(color):
                    item = "\(UIColor(rgb: UInt32(bitPattern: color)).hexString)"
                default:
                    break
            }
            if let item = item {
                if !string.isEmpty {
                    string.append("\n")
                }
                string.append("https://t.me/bg/\(item)")
            }
        }
        let subject: ShareControllerSubject
        if wallpapers.count == 1 {
            subject = .url(string)
        } else {
            subject = .text(string)
        }
        let shareController = ShareController(context: context, subject: subject)
        self.present(shareController, in: .window(.root), blockInteraction: true)
        
        self.donePressed()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationInsetHeight, transition: transition)
    }
    
    func activateSearch() {
        if self.displayNavigationBar {
            let _ = (self.controllerNode.ready.get()
            |> take(1)
            |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                if let scrollToTop = strongSelf.scrollToTop {
                    scrollToTop()
                }
                if let searchContentNode = strongSelf.searchContentNode {
                    strongSelf.controllerNode.activateSearch(placeholderNode: searchContentNode.placeholderNode)
                }
                strongSelf.setDisplayNavigationBar(false, transition: .animated(duration: 0.5, curve: .spring))
            })
        }
    }
    
    func deactivateSearch(animated: Bool) {
        if !self.displayNavigationBar {
            self.setDisplayNavigationBar(true, transition: animated ? .animated(duration: 0.5, curve: .spring) : .immediate)
            if let searchContentNode = self.searchContentNode {
                self.controllerNode.deactivateSearch(placeholderNode: searchContentNode.placeholderNode, animated: animated)
            }
        }
    }
    
    @objc func editPressed() {
        self.editingMode = true
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
        self.searchContentNode?.setIsEnabled(false, animated: true)
        self.controllerNode.updateState { state in
            return state.withUpdatedEditing(true)
        }
    }
    
    @objc func donePressed() {
        self.editingMode = false
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
        self.searchContentNode?.setIsEnabled(true, animated: true)
        self.controllerNode.updateState { state in
            return state.withUpdatedEditing(false)
        }
    }
}