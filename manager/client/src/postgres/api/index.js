export const getDBStates = () => {
  const URL = '/api/postgres/dbstates';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        return response.json().then(json => {
          throw json;
        });
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};

export const getReplicationStats = () => {
  const URL = '/api/postgres/replication_stats';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        return response.json().then(json => {
          throw json;
        });
      }
      return response.json();
    })
    .catch(err => {
      console.log('got error in fetch ' + URL);
      throw err;
    });
};

export const getPgpool = () => {
  const URL = '/api/postgres/pool_nodes';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        return response.json().then(json => {
          throw json;
        });
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};

export const getRepl = () => {
  const URL = '/api/postgres/repl_nodes';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        throw response.statusText;
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};

export const getStatActivity = () => {
  const URL = '/api/postgres/stat_activity';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        throw response.statusText;
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};

export const getBackups = () => {
  const URL = '/api/postgres/backups';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        throw response.statusText;
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};

export const getPgpoolWatchDog = () => {
  const URL = '/api/postgres/pgp_watchdog';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        console.log('response KO');
        if (response.status === 503){
          // TODO: decode response to see if it is really watchdog disabled
          return Promise.reject(new Error('watchdog disabled')) ;
        }
        return Promise.reject(new Error(`Internal error : ${response.status} ${response.statusText}`));
      }
      return response.json();
    })
    .catch((err) => {
      console.log('catched');
      throw err;
    })
};

export const getChecks = () => {
  const URL = '/api/postgres/checks';
  return fetch(URL, { method: 'GET' })
    .then(response => {
      if (!response.ok) {
        throw response.json();
      }
      return response.json();
    })
    .catch(err => {
      throw err;
    });
};
