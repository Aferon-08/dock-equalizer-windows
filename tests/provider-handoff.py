#!/usr/bin/env python3
"""Run production provider functions and dock claim/loader routines under QML."""
from pathlib import Path
import os,subprocess,tempfile
import sys
shell=Path(sys.argv[1]).resolve()
service=(shell/'services/PluginService.qml').read_text()
methods=service[service.index('    function extensionInfo('):service.index('    function openExtensionSettings(')].replace('SettingsService','settingsStore')
dock=(shell/'modules/sekai/dock/Dock.qml').read_text()
a=dock.index('                function syncClaim()');b=dock.index('                onWorkingChanged:',a)
claim=dock[a:b]
a=dock.index('                function loadProvider()');b=dock.index('\n',a)
load=dock[a:b]
with tempfile.TemporaryDirectory(prefix='provider-handoff-') as folder:
 stage=Path(folder);(stage/'ExtensionProviders.js').write_text((shell/'modules/common/functions/ExtensionProviders.js').read_text())
 for name in ['alpha','beta']:
  (stage/name).mkdir();(stage/name/'Dock.qml').write_text('import QtQuick\nItem {required property var host;property bool fits:true;property string providerId:"'+name+'"}')
 qml='''import QtQuick
import Quickshell
import "ExtensionProviders.js" as EP
ShellRoot {
 id:root;settings.watchFiles:false
 property int phase:0
 property var found:[{plugin:{id:"alpha",extensions:["dock"],files:{service:true}}},{plugin:{id:"beta",extensions:["dock"],files:{service:true}}}]
 property var states:({alpha:alpha,beta:beta})
 readonly property var selected:extensionState("dock")
 function stateFor(id){return states[id]}
 QtObject {id:settingsStore;property string value:"{}";function get(key){return value}function set(key,v){value=v}}
 QtObject {id:alpha;property string pluginId:"alpha";property bool loaded:true;property string dir:Quickshell.env("PROVIDER_FIXTURE")+"/alpha";property var plugin:({files:{service:true}})
  property bool enabled:false
  property var claims:({})
  property QtObject service:QtObject {function extensionEnabled(slot){return alpha.enabled}}
  function want(key,on){claims=Object.assign({},claims,{[key]:on})}
 }
 QtObject {id:beta;property string pluginId:"beta";property bool loaded:true;property string dir:Quickshell.env("PROVIDER_FIXTURE")+"/beta";property var plugin:({files:{service:true}})
  property bool enabled:true
  property var claims:({})
  property QtObject service:QtObject {function extensionEnabled(slot){return beta.enabled}}
  function want(key,on){claims=Object.assign({},claims,{[key]:on})}
 }
 Loader {
  id:adapter
  property var st:root.selected
  property var claimedState:null
  property string claimKey:"dock:test"
  readonly property bool working:active && !!item && item.fits
  active:!!st
  QtObject {id:pluginDockHost}
  onStChanged:{syncClaim();Qt.callLater(loadProvider)}
  onActiveChanged:if(active)loadProvider()
  onWorkingChanged:syncClaim()
  Component.onCompleted:{if(active)loadProvider();syncClaim()}
''' +claim+load+'''
 }
 function check(ok,msg){if(!ok){console.error("FAIL "+msg);Qt.quit();return false}return true}
 Timer {interval:60;repeat:true;running:true;onTriggered:{
  const id=adapter.item ? adapter.item.providerId : ""
  if(root.phase===0 && id==="beta" && beta.claims["dock:test"]){alpha.enabled=true;root.phase=1;return}
  if(root.phase===1 && id==="alpha" && alpha.claims["dock:test"]){
   if(!root.check(beta.claims["dock:test"]===false,"old beta lease released"))return
   root.setExtensionProvider("dock","beta");root.phase=2;return
  }
  if(root.phase===2 && id==="beta" && beta.claims["dock:test"]){
   if(!root.check(alpha.claims["dock:test"]===false,"old alpha lease released"))return
   beta.enabled=false;root.phase=3;return
  }
  if(root.phase===3 && id==="alpha" && alpha.claims["dock:test"]){
   if(!root.check(root.extensionInfo("dock").state==="preferred-unavailable","fallback reason"))return
   alpha.enabled=false;root.phase=4;return
  }
  if(root.phase===4 && !root.selected && !adapter.item){
   if(!root.check(!alpha.claims["dock:test"] && !beta.claims["dock:test"],"all leases released"))return
   beta.enabled=true;root.phase=5;return
  }
  if(root.phase===5 && id==="beta" && beta.claims["dock:test"]){console.log("PASS QML automatic selection, explicit provider, disabled fallback, loader replacement and lease release");Qt.quit()}
 }}
 Timer {interval:5000;running:true;onTriggered:{console.error("FAIL provider timeout "+root.phase);Qt.quit()}}
'''+methods+'}\n'
 (stage/'shell.qml').write_text(qml)
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',PROVIDER_FIXTURE=str(stage));env.pop('WAYLAND_DISPLAY',None)
 p=subprocess.run(['dbus-run-session','--','qs','-p',str(stage),'-n'],env=env,text=True,capture_output=True,timeout=8)
 log=p.stdout+p.stderr;print(log,end='')
 if p.returncode or 'FAIL ' in log or 'Error:' in log or 'Binding loop' in log or 'PASS QML automatic' not in log:raise SystemExit('Provider handoff failed')
