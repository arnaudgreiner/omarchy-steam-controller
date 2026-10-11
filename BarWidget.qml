import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Widget de barre autonome : icône 🎮 + panneau de configuration des bindings.
// Le panneau est un PopupCard ancré au widget (pattern du tray).
// Le contenu est découpé en onglets (ButtonGroup) pour que le panneau tienne
// sur un petit écran ; la liste des bindings est scrollable et bornée en hauteur.
BarWidget {
  id: root
  moduleName: "io.github.arnaudgreiner.steam-controller"

  readonly property string backendPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/backend.py"

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

  readonly property var typeOptions: [
    { value: "combo", label: "Combo clavier" },
    { value: "app", label: "App (commande)" },
    { value: "launch", label: "App (omarchy launch)" }
  ]

  readonly property var tabOptions: [
    { value: "profile", label: "Profil" },
    { value: "binding", label: "Nouveau binding" }
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
      newRows.push({ id: r.input, label: r.label, desc: r.desc, bound: r.desc !== "—" && r.desc !== "" })
    }
    root.rows = newRows
  }

  function runSetProfile() {
    if (root.selectedProfile === "") return
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
      newInputs.push({ value: id, label: (labels[id] || id) })
    }
    root.inputs = newInputs
  }

  function runSave() {
    var args = ["python3", root.backendPath, "bind", root.selectedInput, root.selectedType]
    var v = valueField.text.trim()
    if (root.selectedType === "combo") {
      args = args.concat(v.split(/\s+/).filter(function(x) { return x !== "" }))
    } else {
      args.push(v)
    }
    if (root.selectedType === "combo" && args.length <= 5) return
    bindProc.command = args
    bindProc.running = true
  }

  function runClear() {
    bindProc.command = ["python3", root.backendPath, "bind", root.selectedInput, "clear"]
    bindProc.running = true
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

  Process {
    id: bindProc
    command: []
    onRunningChanged: if (!running) root.refresh()
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: applyProc
    command: ["python3", root.backendPath, "apply"]
    onRunningChanged: if (!running) root.refresh()
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: setProfileProc
    command: []
    onRunningChanged: if (!running) root.refresh()
    stdout: StdioCollector { waitForEnd: true }
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
      ? "Steam Controller connecté (profil Omarchy)"
      : (root.daemonOn ? "Steam Controller non connecté" : "Daemon sc-controller arrêté")
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
        text: root.status.controller ? "🎮 Manette connectée" : "🎮 Manette non connectée"
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
          label: "Profil actif"
          value: root.selectedProfile
          options: root.profileList
          onChanged: function(v) { root.selectedProfile = v; root.refreshProfileInputs() }
        }

        Button {
          text: "Activer le profil"
          onClicked: root.runSetProfile()
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        Text {
          text: "Bindings du profil"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Liste bornée en hauteur et scrollable : le panneau tient sur petit écran.
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
          label: "Input"
          value: root.selectedInput
          options: root.inputs
          onChanged: function(v) { root.selectedInput = v }
        }

        Dropdown {
          id: typeDropdown
          width: parent.width
          label: "Action"
          value: root.selectedType
          options: root.typeOptions
          onChanged: function(v) { root.selectedType = v }
        }

        TextField {
          id: valueField
          width: parent.width
          placeholderText: root.selectedType === "combo"
            ? "ex : super c  (touches séparées par des espaces)"
            : (root.selectedType === "app" ? "ex : firefox" : "ex : browser")
        }

        Row {
          width: parent.width
          spacing: Style.spacing.controlGap
          Button {
            text: "Enregistrer"
            onClicked: root.runSave()
          }
          Button {
            text: "Effacer"
            onClicked: root.runClear()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.popups.border
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap
        Button {
          text: "Appliquer"
          onClicked: applyProc.running = true
        }
        Button {
          text: "Relancer daemon"
          onClicked: daemonProc.running = true
        }
        Button {
          text: "Fermer"
          onClicked: root.close()
        }
      }
    }
  }
}
