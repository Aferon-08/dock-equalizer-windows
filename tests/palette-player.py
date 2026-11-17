"""Silent MPRIS test player controlled by a JSON file. Emits no audio."""
import json
import sys
from gi.repository import Gio, GLib

path = sys.argv[1]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
name = 'org.mpris.MediaPlayer2.sekaipop_palette_test'
node = Gio.DBusNodeInfo.new_for_xml('''<node><interface name="org.mpris.MediaPlayer2.Player">
<property name="PlaybackStatus" type="s" access="read"/>
<property name="Metadata" type="a{sv}" access="read"/>
</interface></node>''')
state = {'status': 'Paused', 'art': ''}

def get_property(connection, sender, object_path, interface, prop):
    if prop == 'PlaybackStatus':
        return GLib.Variant('s', state['status'])
    return GLib.Variant('a{sv}', {'mpris:artUrl': GLib.Variant('s', state['art']),
                                'xesam:title': GLib.Variant('s', 'Palette test')})

bus.register_object('/org/mpris/MediaPlayer2', node.interfaces[0], None, get_property, None)
Gio.bus_own_name_on_connection(bus, name, Gio.BusNameOwnerFlags.NONE, None, None)
def poll():
    global state
    try:
        next_state = json.load(open(path))
        if next_state != state:
            state = next_state
            values = {'PlaybackStatus': GLib.Variant('s', state['status']),
                      'Metadata': get_property(None, None, None, None, 'Metadata')}
            bus.emit_signal(None, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties',
                'PropertiesChanged', GLib.Variant('(sa{sv}as)', ('org.mpris.MediaPlayer2.Player', values, [])))
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return True
GLib.timeout_add(50, poll)
GLib.MainLoop().run()
