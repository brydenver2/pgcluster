/*
 if running outside the swarm, i.e. no access to the docker socket
 you will have to expose the docker remote API
*/
const fs = require('fs');

// Read REPMGRPWD from file or environment
let repmgrPassword = 'rep123';
if (process.env.REPMGRPWD_FILE) {
  try {
    repmgrPassword = fs.readFileSync(process.env.REPMGRPWD_FILE, 'utf8').trim();
    console.log(`REPMGRPWD loaded from file: ${process.env.REPMGRPWD_FILE}`);
  } catch (err) {
    console.error(`Error reading REPMGRPWD_FILE: ${err.message}`);
    repmgrPassword = process.env.REPMGRPWD || 'rep123';
  }
} else if (process.env.REPMGRPWD) {
  repmgrPassword = process.env.REPMGRPWD;
}

const dbs=process.env.PG_BACKEND_NODE_LIST.split(',');
let pg = dbs.map((el)=>{
 let elem = el.split(':');
 return {host: elem[1], port: 5432,user: 'repmgr',password: repmgrPassword,database:'repmgr'}
});

module.exports = {
	pg: pg,
	pgp: {
		'host': process.env.DBHOST || 'pgpool01',
		'port': 9999,
		'user': 'repmgr',
		'password': repmgrPassword,
		'database': 'repmgr'		
	},
	docker: {
		'url': 'http://unix:/var/run/docker.sock:',
		'version': 'v1.27'
	},
	pollInterval: 5000
}
