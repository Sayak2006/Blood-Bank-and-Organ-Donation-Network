'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { URL } = require('node:url');
const oracledb = require('oracledb');

const ROOT = path.resolve(__dirname, '..');
const FRONTEND = path.join(ROOT, 'frontend');
const ENV_FILE = path.join(__dirname, '.env');
const MIME = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.svg':'image/svg+xml', '.json':'application/json; charset=utf-8' };
const BLOOD_GROUPS = new Set(['A+','A-','B+','B-','AB+','AB-','O+','O-']);
const COMPONENTS = new Set(['WHOLE_BLOOD','RBC','PLASMA','PLATELETS']);
const ORGANS = new Set(['KIDNEY','LIVER','HEART','LUNG','PANCREAS','CORNEA']);

function readEnv() {
  if (!fs.existsSync(ENV_FILE)) return;
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (match && !Object.hasOwn(process.env, match[1])) process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
}
readEnv();
const PORT = Number(process.env.PORT || 3000);
let pool;

async function db(sql, binds = {}, options = {}) {
  if (!pool) {
    const { ORACLE_USER, ORACLE_PASSWORD, ORACLE_CONNECT_STRING } = process.env;
    if (!ORACLE_USER || !ORACLE_PASSWORD || !ORACLE_CONNECT_STRING) {
      const e = new Error('Oracle is not configured. Copy backend/.env.example to backend/.env and add your Oracle XE username and password.');
      e.status = 503; throw e;
    }
    pool = await oracledb.createPool({ user: ORACLE_USER, password: ORACLE_PASSWORD, connectString: ORACLE_CONNECT_STRING, poolMin: 1, poolMax: 5, poolIncrement: 1 });
  }
  let connection;
  try {
    connection = await pool.getConnection();
    return await connection.execute(sql, binds, { outFormat: oracledb.OUT_FORMAT_OBJECT, ...options });
  } finally { if (connection) await connection.close(); }
}
function safeInt(value, name, min = 1, max = 1000000) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) throw Object.assign(new Error(`${name} must be a whole number between ${min} and ${max}.`), { status: 400 });
  return n;
}
function required(value, name, max = 100) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) throw Object.assign(new Error(`${name} is required (maximum ${max} characters).`), { status: 400 });
  return value.trim();
}
function choice(value, options, name) {
  const v = required(value, name).toUpperCase();
  if (!options.has(v)) throw Object.assign(new Error(`${name} is not a valid option.`), { status: 400 });
  return v;
}
async function bodyJson(req) {
  let data = ''; for await (const chunk of req) { data += chunk; if (data.length > 100_000) throw Object.assign(new Error('Request body is too large.'), { status: 413 }); }
  try { return JSON.parse(data || '{}'); } catch { throw Object.assign(new Error('Request body must be valid JSON.'), { status: 400 }); }
}
function send(res, status, data) {
  const payload = Buffer.from(JSON.stringify(data));
  res.writeHead(status, { 'Content-Type':'application/json; charset=utf-8', 'Content-Length':payload.length, 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff' }); res.end(payload);
}
const asIso = v => v instanceof Date ? v.toISOString() : v;

async function api(req, res, url) {
  const route = url.pathname;
  if (req.method === 'GET' && route === '/api/health') {
    const result = await db("SELECT 'connected' AS status FROM dual");
    return send(res, 200, { status:'ok', database:result.rows[0].STATUS });
  }
  if (req.method === 'GET' && route === '/api/dashboard') {
    const [donors, stock, requests, waitlist, critical, fulfillment, donorTotal, donationsMonth, fulfilling, organDonors, expiring] = await Promise.all([
      db('SELECT COUNT(*) AS total FROM v_eligible_donors'),
      db("SELECT COUNT(*) AS total FROM blood_unit WHERE status = 'AVAILABLE' AND expiry_on >= TRUNC(SYSDATE)"),
      db("SELECT COUNT(*) AS total FROM blood_request WHERE status = 'PENDING'"),
      db("SELECT COUNT(*) AS total FROM organ_waitlist WHERE status = 'WAITING'"),
      db("SELECT COUNT(*) AS total FROM blood_request r JOIN patient p ON p.patient_id=r.patient_id WHERE r.status='PENDING' AND p.urgency='CRITICAL'"),
      db("SELECT NVL(ROUND(100 * SUM(CASE WHEN status='FULFILLED' THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0),1),0) AS rate FROM blood_request"),
      db('SELECT COUNT(*) AS total FROM donor'),
      db('SELECT COUNT(*) AS total FROM blood_unit WHERE collected_on >= TRUNC(SYSDATE,\'MM\')'),
      db('SELECT COUNT(DISTINCT request_id) AS total FROM blood_issue WHERE issued_on >= TRUNC(SYSDATE)'),
      db("SELECT COUNT(*) AS total FROM organ_donor WHERE status='AVAILABLE'"),
      db("SELECT COUNT(*) AS total FROM blood_unit WHERE status='AVAILABLE' AND expiry_on BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE)+7")
    ]);
    return send(res, 200, { activeDonors:donors.rows[0].TOTAL, eligibleDonors:donors.rows[0].TOTAL, donorTotal:donorTotal.rows[0].TOTAL, donationsMonth:donationsMonth.rows[0].TOTAL, unitsAvailable:stock.rows[0].TOTAL, expiringUnits:expiring.rows[0].TOTAL, fulfillmentRate:fulfillment.rows[0].RATE, fulfilledToday:fulfilling.rows[0].TOTAL, pendingRequests:requests.rows[0].TOTAL, organWaitlist:waitlist.rows[0].TOTAL, organDonors:organDonors.rows[0].TOTAL, criticalRequests:critical.rows[0].TOTAL });
  }
  if (req.method === 'GET' && route === '/api/stock') {
    const bankId=url.searchParams.get('bankId') ? safeInt(url.searchParams.get('bankId'),'Bank ID') : null;
    const bankClause=bankId===null?'':' AND b.bank_id=:bankId';
    const { rows } = await db(`SELECT blood_group, COUNT(*) AS units, MIN(bank_name) AS bank_name
      FROM (SELECT u.blood_group, b.name AS bank_name FROM blood_unit u JOIN blood_bank b ON b.bank_id=u.bank_id
        WHERE u.status='AVAILABLE' AND u.expiry_on >= TRUNC(SYSDATE)${bankClause})
      GROUP BY blood_group ORDER BY COUNT(*) ASC, blood_group`, bankId===null?{}:{bankId});
    return send(res, 200, rows.map(r => ({ group:r.BLOOD_GROUP, units:r.UNITS, bankName:r.BANK_NAME, level:r.UNITS < 15 ? 'low' : 'healthy', status:r.UNITS < 5 ? 'Urgent' : r.UNITS < 15 ? 'Low stock' : 'Healthy' })));
  }
  if (req.method === 'GET' && route === '/api/requests') {
    const { rows } = await db(`SELECT r.request_id, r.blood_group, r.units_needed, r.requested_on, r.component, p.name AS patient_name,
      p.urgency, h.name AS hospital FROM blood_request r JOIN patient p ON p.patient_id=r.patient_id JOIN hospital h ON h.hospital_id=r.hospital_id
      WHERE r.status='PENDING' ORDER BY CASE p.urgency WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, r.requested_on`);
    return send(res, 200, rows.map(r => ({ id:r.REQUEST_ID, group:r.BLOOD_GROUP, name:r.PATIENT_NAME, hospital:r.HOSPITAL, units:r.UNITS_NEEDED, when:asIso(r.REQUESTED_ON), urgency:r.URGENCY.toLowerCase(), component:r.COMPONENT })));
  }
  if (req.method === 'GET' && route === '/api/donors') {
    const { rows } = await db(`SELECT donor_id, name, blood_group, city, last_donation_date,
      CASE WHEN EXISTS (SELECT 1 FROM v_eligible_donors e WHERE e.donor_id=d.donor_id) THEN 'Eligible' ELSE 'Resting' END AS eligibility
      FROM donor d ORDER BY last_donation_date DESC NULLS LAST, donor_id DESC FETCH FIRST 30 ROWS ONLY`);
    return send(res, 200, rows.map(r => ({ id:r.DONOR_ID, name:r.NAME, group:r.BLOOD_GROUP, city:r.CITY, lastDonation:asIso(r.LAST_DONATION_DATE), eligibility:r.ELIGIBILITY })));
  }
  if (req.method === 'GET' && route === '/api/waitlist') {
    const { rows } = await db(`SELECT w.waitlist_id, w.organ_type, p.name AS patient_name, p.blood_group, w.medical_urgency,
      w.registered_on, v.queue_position FROM organ_waitlist w JOIN patient p ON p.patient_id=w.patient_id
      LEFT JOIN v_organ_waitlist_ranking v ON v.waitlist_id=w.waitlist_id WHERE w.status='WAITING'
      ORDER BY w.medical_urgency DESC, w.registered_on ASC`);
    return send(res, 200, rows.map(r => ({ id:r.WAITLIST_ID, organ:r.ORGAN_TYPE, name:r.PATIENT_NAME, group:r.BLOOD_GROUP, urgency:r.MEDICAL_URGENCY, registered:asIso(r.REGISTERED_ON), score:r.QUEUE_POSITION })));
  }
  if (req.method === 'GET' && route === '/api/activity') {
    const { rows } = await db('SELECT table_name, action, details, changed_on FROM audit_log ORDER BY changed_on DESC FETCH FIRST 8 ROWS ONLY');
    return send(res, 200, rows.map(r => ({ table:r.TABLE_NAME, action:r.ACTION, details:r.DETAILS, at:asIso(r.CHANGED_ON) })));
  }
  if (req.method === 'GET' && route === '/api/options') {
    const [banks, hospitals, patients, donors, organs] = await Promise.all([
      db('SELECT bank_id, name, city FROM blood_bank ORDER BY name'),
      db('SELECT hospital_id, name, city FROM hospital ORDER BY name'),
      db('SELECT p.patient_id, p.name, p.blood_group, p.urgency, h.name AS hospital FROM patient p JOIN hospital h ON h.hospital_id=p.hospital_id ORDER BY p.name'),
      db('SELECT donor_id, name, blood_group FROM v_eligible_donors ORDER BY name'),
      db("SELECT organ_donor_id, organ_type, d.name AS donor_name, d.blood_group FROM organ_donor od JOIN donor d ON d.donor_id=od.donor_id WHERE od.status='AVAILABLE' ORDER BY od.organ_type, d.name")
    ]);
    return send(res, 200, {
      banks:banks.rows.map(r=>({id:r.BANK_ID,name:r.NAME,city:r.CITY})),
      hospitals:hospitals.rows.map(r=>({id:r.HOSPITAL_ID,name:r.NAME,city:r.CITY})),
      patients:patients.rows.map(r=>({id:r.PATIENT_ID,name:r.NAME,group:r.BLOOD_GROUP,urgency:r.URGENCY,hospital:r.HOSPITAL})),
      eligibleDonors:donors.rows.map(r=>({id:r.DONOR_ID,name:r.NAME,group:r.BLOOD_GROUP})),
      organDonors:organs.rows.map(r=>({id:r.ORGAN_DONOR_ID,organ:r.ORGAN_TYPE,name:r.DONOR_NAME,group:r.BLOOD_GROUP}))
    });
  }
  if (req.method === 'POST' && route === '/api/requests') {
    const b=await bodyJson(req), patientId=safeInt(b.patientId,'Patient'), units=safeInt(b.units,'Units',1,999), component=choice(b.component||'WHOLE_BLOOD',COMPONENTS,'Component');
    const result=await db(`INSERT INTO blood_request (hospital_id, patient_id, blood_group, component, units_needed, status, requested_on)
      SELECT hospital_id, patient_id, blood_group, :component, :units, 'PENDING', SYSDATE FROM patient WHERE patient_id=:patientId`,
      {component,units,patientId}, {autoCommit:true});
    if (!result.rowsAffected) throw Object.assign(new Error('Patient was not found.'),{status:404});
    return send(res,201,{message:'Blood request added to the queue.'});
  }
  const fulfill=route.match(/^\/api\/requests\/(\d+)\/fulfill$/);
  if (req.method==='POST' && fulfill) {
    await db('BEGIN blood_mgmt_pkg.fulfill_request(:id); END;', {id:safeInt(fulfill[1],'Request ID')});
    return send(res,200,{message:'Request fulfilled and inventory updated.'});
  }
  if (req.method === 'POST' && route === '/api/donations') {
    const b=await bodyJson(req), donorId=safeInt(b.donorId,'Donor'), bankId=safeInt(b.bankId,'Blood bank'), component=choice(b.component||'WHOLE_BLOOD',COMPONENTS,'Component');
    await db('BEGIN blood_mgmt_pkg.register_donation(:donor_id, :bank_id, :component); END;', {donor_id:donorId,bank_id:bankId,component});
    return send(res,201,{message:'Donation recorded; donor and stock updated.'});
  }
  if (req.method === 'POST' && route === '/api/donors') {
    const b=await bodyJson(req), name=required(b.name,'Name'), dob=required(b.dob,'Date of birth',10), group=choice(b.group,BLOOD_GROUPS,'Blood group'), city=required(b.city,'City'), gender=choice(b.gender,new Set(['M','F','O']),'Gender'), phone=typeof b.phone==='string'&&b.phone.trim()?b.phone.trim():null;
    await db(`INSERT INTO donor (name,dob,gender,blood_group,phone,city) VALUES (:name,TO_DATE(:dob,'YYYY-MM-DD'),:gender,:bloodGroup,:phone,:city)`,{name,dob,gender,bloodGroup:group,phone,city},{autoCommit:true});
    return send(res,201,{message:'Donor profile created.'});
  }
  if (req.method === 'POST' && route === '/api/waitlist') {
    const b=await bodyJson(req), patientId=safeInt(b.patientId,'Patient'), organ=choice(b.organ,ORGANS,'Organ'), urgency=safeInt(b.urgency,'Urgency',1,10), hla=typeof b.hla==='string'&&b.hla.trim()?b.hla.trim():null;
    const result=await db(`INSERT INTO organ_waitlist (patient_id,organ_type,medical_urgency,hla_type,registered_on,status)
      VALUES (:patientId,:organ,:urgency,:hla,SYSDATE,'WAITING')`,{patientId,organ,urgency,hla},{autoCommit:true});
    return send(res,201,{message:'Patient added to the organ waitlist.'});
  }
  if (req.method === 'POST' && route === '/api/organ-match') {
    const b=await bodyJson(req), donorId=safeInt(b.organDonorId,'Organ donor');
    await db('BEGIN organ_mgmt_pkg.find_organ_match(:id); END;', {id:donorId});
    return send(res,200,{message:'The best compatible waitlist match has been created.'});
  }
  send(res,404,{error:'API route not found.'});
}

function serveFile(req,res,url) {
  let pathname=decodeURIComponent(url.pathname);
  if (pathname==='/' || pathname==='/index.html') pathname='/frontend/index.html';
  else if (!pathname.startsWith('/frontend/')) pathname='/frontend'+pathname;
  const target=path.resolve(ROOT, '.'+pathname);
  if (!target.startsWith(FRONTEND+path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) { res.writeHead(404); return res.end('Not found'); }
  res.writeHead(200,{'Content-Type':MIME[path.extname(target)]||'application/octet-stream','X-Content-Type-Options':'nosniff'});fs.createReadStream(target).pipe(res);
}
const server=http.createServer(async(req,res)=>{
  const url=new URL(req.url,`http://${req.headers.host||'localhost'}`);
  try { if(url.pathname.startsWith('/api/')) await api(req,res,url); else if(req.method==='GET') serveFile(req,res,url); else send(res,405,{error:'Method not allowed.'}); }
  catch(error){ const status=error.status||500; if(status>=500) console.error(error); send(res,status,{error:status>=500?'Database operation failed. Check the server terminal and Oracle connection settings.':error.message}); }
});
server.listen(PORT,()=>console.log(`BloodNet running at http://localhost:${PORT}`));
async function shutdown(){server.close();if(pool)await pool.close(10);process.exit(0)}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
