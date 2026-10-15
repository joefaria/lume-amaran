// Independent validation using Node/OpenSSL AES; contains ONLY published test keys.
import crypto from 'node:crypto';
import fs from 'node:fs';
const B = x => Buffer.from(x, 'hex');
const net = B('00112233445566778899aabbccddeeff');
const app = B('ffeeddccbbaa99887766554433221100');
const xor = (a,b) => Buffer.from([...a].map((x,i)=>x^b[i]));
function aes(k,d) { const c=crypto.createCipheriv('aes-128-ecb',k,null);c.setAutoPadding(false);return Buffer.concat([c.update(d),c.final()]); }
function shift(b) { const n=(BigInt('0x'+b.toString('hex'))<<1n)^((b[0]&128)?0x87n:0n);return B((n&((1n<<128n)-1n)).toString(16).padStart(32,'0')); }
function cmac(k,m) { const k1=shift(aes(k,Buffer.alloc(16)));const k2=shift(k1);const n=Math.max(1,Math.ceil(m.length/16));let x=Buffer.alloc(16);for(let i=0;i<n-1;i++)x=aes(k,xor(x,m.subarray(i*16,i*16+16)));let last=Buffer.alloc(16);m.subarray((n-1)*16).copy(last);if(m.length&&m.length%16===0)last=xor(last,k1);else{last[m.length%16]=128;last=xor(last,k2);}return aes(k,xor(x,last)); }
const s1=m=>cmac(Buffer.alloc(16),Buffer.from(m));
function ccm(key,nonce,data,mic) {const c=crypto.createCipheriv('aes-128-ccm',key,nonce,{authTagLength:mic});c.setAAD(Buffer.alloc(0),{plaintextLength:data.length});const p=c.update(data);c.final();return Buffer.concat([p,c.getAuthTag()]);}
const t=cmac(s1('smk2'),net),t1=cmac(t,B('0001')),t2=cmac(t,Buffer.concat([t1,B('0002')])),t3=cmac(t,Buffer.concat([t2,B('0003')]));
const aid=cmac(cmac(s1('smk4'),app),B('69643601'))[15]&63;
function network(plain,seq,proxy){const seqb=B(seq.toString(16).padStart(6,'0')),src=B('7000'),iv=Buffer.alloc(4),ctl=proxy?128:7;const nonce=Buffer.concat([Buffer.from([proxy?3:0,proxy?0:ctl]),seqb,src,B('0000'),iv]);const enc=ccm(t2,nonce,plain,proxy?8:4);const pecb=aes(t3,Buffer.concat([Buffer.alloc(5),iv,enc.subarray(0,7)]));const hdr=Buffer.concat([Buffer.from([ctl]),seqb,src]);return Buffer.concat([Buffer.from([proxy?2:0,t1[15]&127]),xor(hdr,pecb),enc]).toString('hex');}
const access=B('268d00000000000000018c'),nonce=B('01000000017000000200000000');
const upper=ccm(app,nonce,access,4);
const result={network:cmac(cmac(s1('smk3'),net),B('6964363401')).subarray(8).toString('hex'),ccm4:upper.toString('hex'),ccm8:ccm(app,nonce,access,8).toString('hex'),packet:network(Buffer.concat([B('0002'),Buffer.from([64|aid]),upper]),1,false),filter:network(B('00000001'),2,true)};
fs.writeFileSync(process.argv[2],JSON.stringify(result));
