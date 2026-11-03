#!/usr/bin/env python3
"""Use tiny local fixtures; don't read recordings or load ML models."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import analysis_identity as analysis
import wordtime

with tempfile.TemporaryDirectory(prefix='dock-fingerprint-test-') as tmp:
    os.environ['XDG_DATA_HOME'] = tmp
    root = Path(tmp)
    audio = root / 'audio'
    audio.write_bytes(b'fixture audio')
    model = root / 'model'
    model.write_bytes(b'fixture weights')
    models = {'whisper': model}
    settings = {'multivoice': True}

    def fingerprint(text='abc', config=settings):
        return analysis.fingerprint(audio, text, None, models, config)

    first = fingerprint()
    assert first == fingerprint('abc\r\n')
    assert str(root) not in json.dumps(first)
    assert fingerprint('different text')['key'] != first['key']
    assert fingerprint(config={'multivoice': False})['key'] != first['key']
    model.write_bytes(b'new weights')
    assert fingerprint()['models'] != first['models']
    audio.write_bytes(b'another recording')
    assert fingerprint()['audio'] != first['audio']
    assert analysis.state({}, {'fullScan': True}, True) == 'complete'
    assert analysis.state({}, {'fullScan': False, 'budgetLimited': True}, True) == 'partial'
    assert analysis.state({}, {'fullScan': True, 'status': 'failed'}, True) == 'failed'
    assert analysis.state({'words':[{'status':'review'}]}, {'fullScan': True}, True) == 'review'

    track = {'title':'Test', 'artist':'Fixture', 'duration':20}
    document = {'duration':20, 'words':[{'word':'Hi','line':0,'start':1,'end':2}],
        'analysis':{'revision':analysis.REVISION,'state':'partial','fingerprint':first},
        'multivoice':{'fullScan':False,'budgetLimited':True}}
    wordtime.save_result(document, track)
    args = argparse.Namespace(action='lookup', track_json=json.dumps(track), file='')
    result = wordtime.run(args)
    assert result['analysis']['fingerprint'] == first and result['multivoice']['budgetLimited']
    imported = root / 'import.json'
    imported.write_text(json.dumps(document))
    args.action = 'import'
    args.file = str(imported)
    assert wordtime.run(args)['analysis']['origin'] == 'import'
print('PASS content hashes, status distinction, metadata round trip and import origin')
