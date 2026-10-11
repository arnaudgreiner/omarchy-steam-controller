import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

// Self-contained bar widget: 🎮 icon + binding configuration panel.
// The panel is a PopupCard anchored to the widget (tray pattern).
// Content is split into tabs (ButtonGroup) so the panel fits small
// screens; the bindings list is scrollable and height-capped.
BarWidget {
  id: root
  moduleName: "io.github.arnaudgreiner.steam-controller"

  readonly property string backendPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/backend.py"

  // UI language: English by default, French when the system locale is French.
  readonly property string lang: Qt.locale().name.substring(0, 2)

  property bool controllerOn: false
  property bool daemonOn: false
  property bool panelOpen: false

  // État des bindings
  property var status: ({})
  property var rows: []
  property var inputs: []
  property string selectedInput: "A"
  property string selectedType: "combo"
  property var profileList: []
  property string currentProfile: ""
  property string selectedProfile: ""

  // Onglet actif du panneau : "profile" ou "binding"
  property string activeTab: "profile"

  // Panel feedback (result messages)
  property string feedback: ""
  property string pendingFeedback: ""

  onActiveTabChanged: {
    root.feedback = ""
    if (activeTab === "binding") Qt.callLater(function() { valueField.forceActiveFocus() })
  }

  readonly property var typeOptions: [
    { value: "combo", label: I18n.t("typeCombo", root.lang) },
    { value: "app", label: I18n.t("typeApp", root.lang) },
    { value: "launch", label: I18n.t("typeLaunch", root.lang) }
  ]

  readonly property var tabOptions: [
    { value: "profile", label: I18n.t("tabProfile", root.lang) },
    { value: "binding", label: I18n.t("tabBinding", root.lang) }
  ]

  // Contrat open/close/opened pour la barre (summon/toggle par hotkey)
  readonly property bool opened: panelOpen
  function open() { panelOpen = true }
  function close() { panelOpen = false }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function applyProfiles(text) {
    var parsed = {}
    try { parsed = JSON.parse(text || "{}") } catch (e) {}
    root.profileList = parsed.profiles || []
    root.currentProfile = parsed.current || ""
    if (root.selectedProfile === "" || root.profileList.indexOf(root.selectedProfile) === -1) {
      root.selectedProfile = root.currentProfile !== ""
        ? root.currentProfile
        : (root.profileList.length > 0 ? root.profileList[0] : "")
    }
    root.refreshProfileInputs()
  }

  function refreshProfileInputs() {
    if (root.selectedProfile === "") return
    profileInputsProc.command = ["python3", root.backendPath, "profile-inputs", root.selectedProfile]
    profileInputsProc.running = true
  }

  function applyProfileInputs(text) {
    var parsed = {}
    try { parsed = JSON.parse(text || "{}") } catch (e) {}
    var ins = parsed.inputs || []
    var newRows = []
    for (var i = 0; i < ins.length; i++) {
      var r = ins[i]
      var lab = I18n.t("input." + r.input, root.lang)
      if (lab === "input." + r.input) lab = r.label
      newRows.push({ id: r.input, label: lab, desc: r.desc, bound: r.desc !== "—" && r.desc !== "" })
    }
    root.rows = newRows
  }

  function runSetProfile() {
    if (root.selectedProfile === "") return
    root.pendingFeedback = I18n.t("fbProfileActivated", root.lang) + root.selectedProfile
    setProfileProc.command = ["python3", root.backendPath, "set-profile", root.selectedProfile]
    setProfileProc.running = true
  }

  function applyStatus(text) {
    var parsed = {}
    try { parsed = JSON.parse(text || "{}") } catch (e) {}
    root.status = parsed
    root.controllerOn = parsed.controller === true
    root.daemonOn = parsed.daemon === true
    var labels = parsed.input_labels || {}
    var ins = parsed.inputs || []
    var newInputs = []
    for (var i = 0; i < ins.length; i++) {
      var id = ins[i]
      var lab = I18n.t("input." + id, root.lang)
      if (lab === "input." + id) lab = (labels[id] || id)
      newInputs.push({ value: id, label: lab })
    }
    root.inputs = newInputs
  }

  function runSave() {
    var args = ["python3", root.backendPath, "bind", root.selectedInput, root.selectedType]
    var v = valueField.text.trim()
    if (root.selectedType === "combo") {
      args = args.concat(v.split(/\s+/).filter(function(x) { return x !== "" }))
      if (args.length <= 5) { root.feedback = I18n.t("fbMissingCombo", root.lang); return }
    } else {
      if (v === "") { root.feedback = I18n.t("fbMissingValue", root.lang); return }
      args.push(v)
    }
    root.pendingFeedback = I18n.t("fbSaved", root.lang) + root.selectedInput + " → " + v
    bindProc.command = args
    bindProc.running = true
  }

  function runClear() {
    root.pendingFeedback = I18n.t("fbRemoved", root.lang) + root.selectedInput
    bindProc.command = ["python3", root.backendPath, "bind", root.selectedInput, "clear"]
    bindProc.running = true
  }

  function runApply() {
    root.pendingFeedback = I18n.t("fbApplied", root.lang)
    applyProc.running = true
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: ["python3", root.backendPath, "status"]
    onRunningChanged: if (!running) statusTimer.restart()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Timer {
    id: statusTimer
    interval: 5000
    onTriggered: root.refresh()
  }

  Process {
    id: profilesProc
    command: ["python3", root.backendPath, "profiles"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfiles(text)
    }
  }

  Process {
    id: profileInputsProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfileInputs(text)
    }
  }

  // Enregistrement -> puis application automatique au profil
  Process {
    id: bindProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.indexOf("OK") === 0) {
          applyProc.running = true
        } else {
          root.feedback = I18n.t("fbSaveError", root.lang) + (text || "")
          root.refresh()
        }
      }
    }
  }

  Process {
    id: applyProc
    command: ["python3", root.backendPath, "apply"]
    onRunningChanged: if (!running) root.refresh()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.feedback = text.indexOf("OK") === 0 ? root.pendingFeedback : I18n.t("fbApplyError", root.lang)
        root.pendingFeedback = ""
      }
    }
  }

  Process {
    id: setProfileProc
    command: []
    onRunningChanged: if (!running) root.refresh()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.feedback = text.indexOf("OK") === 0 ? root.pendingFeedback : I18n.t("fbError", root.lang) + (text || "")
        root.pendingFeedback = ""
      }
    }
  }

  Process {
    id: daemonProc
    command: ["scc-daemon", "restart"]
    onRunningChanged: if (!running) restartTimer.start()
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer { id: restartTimer; interval: 1500; onTriggered: root.refresh() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🎮"
    dimmed: !root.controllerOn
    tooltipText: root.controllerOn
      ? I18n.t("statusConnected", root.lang)
      : (root.daemonOn ? I18n.t("statusDisconnected", root.lang) : I18n.t("statusDaemonOff", root.lang))
    onPressed: function(b) { root.panelOpen = !root.panelOpen }
  }

  PopupCard {
    id: popup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.panelOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    Column {
      id: contentColumn
      width: popup.contentWidth
      spacing: Style.spacing.controlGap

      Text {
        text: root.status.controller ? I18n.t("controllerConnected", root.lang) : I18n.t("controllerDisconnected", root.lang)
        color: root.status.controller ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.popups.border
      }

      // Onglets : Profil (vue + liste des bindings) / Nouveau binding (formulaire)
      ButtonGroup {
        id: tabGroup
        width: parent.width
        options: root.tabOptions
        value: root.activeTab
        onChanged: function(v) { root.activeTab = v }
      }

      // ---- Onglet Profil -------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.spacing.controlGap
        visible: root.activeTab === "profile"

        Dropdown {
          id: profileDropdown
          width: parent.width
          label: I18n.t("activeProfile", root.lang)
          value: root.selectedProfile
          options: root.profileList
          onChanged: function(v) { root.selectedProfile = v; root.refreshProfileInputs() }
        }

        Button {
          text: I18n.t("applyProfile", root.lang)
          onClicked: root.runSetProfile()
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        Text {
          text: I18n.t("profileBindings", root.lang)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Height-capped scrollable list: the panel fits small screens.
        ListView {
          id: bindingsList
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          model: root.rows
          clip: true
          spacing: 0
          boundsBehavior: Flickable.StopAtBounds

          delegate: Row {
            required property var modelData
            width: bindingsList.width
            height: Style.spacing.controlHeight
            Text {
              width: 150
              text: modelData.label
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width - 150
              text: modelData.desc
              color: modelData.bound ? Color.accent : Qt.darker(Color.foreground, 1.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      // ---- Onglet Nouveau binding ---------------------------------------
      Column {
        width: parent.width
        spacing: Style.spacing.controlGap
        visible: root.activeTab === "binding"

        Dropdown {
          id: inputDropdown
          width: parent.width
          label: I18n.t("inputLabel", root.lang)
          value: root.selectedInput
          options: root.inputs
          onChanged: function(v) { root.selectedInput = v }
        }

        Dropdown {
          id: typeDropdown
          width: parent.width
          label: I18n.t("actionLabel", root.lang)
          value: root.selectedType
          options: root.typeOptions
          onChanged: function(v) { root.selectedType = v }
        }

        TextField {
          id: valueField
          width: parent.width
          placeholderText: root.selectedType === "combo"
            ? I18n.t("placeholderCombo", root.lang)
            : (root.selectedType === "app" ? I18n.t("placeholderApp", root.lang) : I18n.t("placeholderLaunch", root.lang))
        }

        Row {
          width: parent.width
          spacing: Style.spacing.controlGap
          Button {
            text: I18n.t("save", root.lang)
            onClicked: root.runSave()
          }
          Button {
            text: I18n.t("clear", root.lang)
            onClicked: root.runClear()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.popups.border
      }

      Text {
        visible: root.feedback !== ""
        width: parent.width
        text: root.feedback
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap
        Button {
          text: I18n.t("apply", root.lang)
          onClicked: root.runApply()
        }
        Button {
          text: I18n.t("restartDaemon", root.lang)
          onClicked: daemonProc.running = true
        }
        Button {
          text: I18n.t("close", root.lang)
          onClicked: root.close()
        }
      }
    }
  }
}
