import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const p = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../AnalysisPolicy.js', import.meta.url), 'utf8').replace(/^\.pragma.*$/m, ''), p);
const source = '[00:05.00]A short line', snapshot = {voices:'new-models'};
const result = {status:'ready', analysis:{revision:p.revision, sourceSignature:p.signature(source),
    fingerprint:{modelSnapshot:'new-models'}, state:'review', voices:'estimated', textScanComplete:true},
    multivoice:{budgetLimited:false, fullScan:true}};
const reason = (value, text=source, enabled=true, ready=true) => p.updateReason(value, enabled, text, ready, snapshot);
assert.equal(reason(result), '', 'review alone does not mean unfinished');
assert.equal(reason({...result,multivoice:{fullScan:false,budgetLimited:true}}), 'partial');
assert.equal(reason({...result,analysis:{...result.analysis,voices:'failed'}}), 'failed');
assert.equal(reason({...result,status:'partial'}), 'timings');
assert.equal(reason(result,'another provider text'), 'source');
assert.equal(reason(result,null), '', 'do not compare a transient missing provider source');
assert.equal(reason({...result,analysis:{...result.analysis,fingerprint:{modelSnapshot:'old-models'}}}), 'models');
assert.equal(reason({...result,analysis:{...result.analysis,state:'partial'}},source,false), '');
assert.equal(reason({status:'ready', analysis:{origin:'import'}},source,false), '');
console.log('PASS completed review vs retryable partial/failed, changed text and models, import retention');
