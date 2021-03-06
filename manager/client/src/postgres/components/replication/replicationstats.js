/* eslint-disable react/no-unused-prop-types */
/* eslint-disable react/require-default-props */
import React, { Component } from 'react';
import { PropTypes } from 'prop-types';
import ShellConsoleModal from '../../../shared/components/shellconsolemodal';
import StateUpDown from '../../../shared/components/stateupdown';

const Stats = ({ data }) => {
  if (!data) {
    return <div>no data</div>;
  }
  const rows = data.map((row, idx) => <Stat key={idx} {...row} />);

  return <div>{rows}</div>;
};
// this is the result of a select on pg_stat_wal_receiver
// or on pg_stat_replication
Stats.propTypes = {
  // case data is from pg_stat_replication
  procpid: PropTypes.number,
  usesysid: PropTypes.string,
  usename: PropTypes.string,
  application_name: PropTypes.string,
  client_addr: PropTypes.string,
  client_port: PropTypes.number,
  backend_start: PropTypes.string,
  state: PropTypes.string,
  sent_location: PropTypes.string,
  write_location: PropTypes.string,
  flush_location: PropTypes.string,
  replay_location: PropTypes.string,
  sync_priority: PropTypes.string,
  sync_state: PropTypes.string,
  // case data is coming from pg_stat_wal_receiver
  pid: PropTypes.number,
  status: PropTypes.string,
  receive_start_lsn: PropTypes.string,
  receive_start_tli: PropTypes.string,
  received_lsn: PropTypes.string,
  received_tli: PropTypes.number,
  last_msg_send_time: PropTypes.string,
  last_msg_receipt_time: PropTypes.string,
  latest_end_lsn: PropTypes.string,
  latest_end_time: PropTypes.string,
  slot_name: PropTypes.string,
  conninfo: PropTypes.string,
};

const Stat = data => {
  const rows = [];
  // eslint-disable-next-line no-restricted-syntax
  for (const prop of Object.keys(data)) {
    /*
    if (typeof data[prop] === "object" && data[prop]) {
      val = data[prop]["milliseconds"]
        ? data[prop]["milliseconds"] + " ms"
        : "Object";
    } else {
      val = data[prop];
    }
    */
    if (
      prop === 'pid' ||
      prop === 'usesysid' ||
      prop === 'usename' ||
      prop === 'client_hostname' ||
      prop === 'client_port'
      // eslint-disable-next-line no-empty
    ) {
    } else if (prop === 'write_lag' || prop === 'replay_lag' || prop === 'flush_lag') {
      const val = data[prop];
      if (val) {
        let result = '';
        const lagProps = Object.keys(val);
        if (lagProps.includes('milliseconds')) {
          result = `${val.milliseconds} ms`;
        } else if (lagProps.includes('second')) {
          result = `${val.seconds} s ${result}`;
        } else if (lagProps.includes('minutes')) {
          result = `${val.minutes} min ${result}`;
        } else if (lagProps.includes('hours')) {
          result = `${val.hours} h ${result}`;
        } else if (lagProps.includes('days')) {
          result = `${val.hours} days ${result}`;
        }
        rows.push(
          <tr key={prop}>
            <td>{prop}</td>
            <td>{result}</td>
          </tr>
        );
      }
    } else {
      rows.push(
        <tr key={prop}>
          <td>{prop}</td>
          <td>{data[prop]}</td>
        </tr>
      );
    }
  }
  return (
    <table className="table table-bordered table-condensed">
      <thead />
      <tbody>{rows}</tbody>
    </table>
  );
};

const StateStatus = ({ color }) => {
  /*
	return (
		<svg width="40" height="30">
   			<circle cx="20" cy="20" r="10" fill={color} />		
			</svg>
	) 
	*/
  if (color === 'green') {
    return <span style={{ color: 'green', fontWeight: 'bold' }}>V</span>;
  }
  if (color === 'red') {
    return <span style={{ color: 'red' }}>X</span>;
  }
};

const Backend = ({ host, backend, onConsoleAction }) => {
  const pgpoolColor =
    backend.pgpool_status === 'up' || backend.pgpool_status === 'waiting' ? 'success' : 'danger';
  const pcpAttachClass =
    backend.pgpool_status === 'down' ? 'btn btn-primary enabled' : 'btn btn-primary disabled';
  const pcpDetachClass =
    backend.pgpool_status === 'up' || backend.pgpool_status === 'waiting'
      ? 'btn btn-primary enabled'
      : 'btn btn-primary disabled';
  const pgStopClass =
    backend.status === 'green' ? 'btn btn-primary enabled' : 'btn btn-primary disabled';
  const pgStartClass =
    backend.status === 'green' ? 'btn btn-primary disabled' : 'btn btn-primary  enabled';
  const repmgrUnregisterClass =
    backend.active && backend.role === 'standby'
      ? 'btn btn-primary  enabled'
      : 'btn btn-primary disabled';
  const masterClass = backend.role === 'primary' ? 'alert success' : 'alert warning';
  const tabStyleMaster = { border: 'solid 2px green' };
  const tabStyleStandby = {};
  const recoveryNodeBtnClass =
    backend.pgpool_status === 'down' ? 'btn btn-block' : 'btn btn-block disabled';

  return (
    <div className="col-md-4">
      <table
        className="table table-bordered table-condensed"
        style={backend.role === 'master' ? tabStyleMaster : tabStyleStandby}
      >
        <thead />
        <tbody>
          <tr>
            <td>
              <StateUpDown color={backend.status} />
            </td>
            <td>{host}</td>
            <td>{backend.status}</td>
            <td>
              <div className="btn-group" role="group" aria-label="pgpool actions">
                <button
                  className={pgStopClass}
                  style={{ marginRight: 5 }}
                  onClick={onConsoleAction.bind(null, host, 'pg_stop')}
                >
                  Stop
                </button>
                <button
                  className={pgStartClass}
                  onClick={onConsoleAction.bind(null, host, 'pg_start')}
                >
                  Start
                </button>
              </div>
            </td>
          </tr>
          <tr>
            <td />
            <td>Repmgr role</td>
            <td>{backend.role === 'master' ? '** master **' : backend.role}</td>
            <td />
          </tr>
          <tr>
            <td>
              <StateStatus color={backend.active ? 'green' : 'red'} />
            </td>
            <td>Repmgr active</td>
            <td>{backend.active ? 'yes' : 'no'}</td>
            <td>
              <div className="btn-group" role="group" aria-label="pgpool actions">
                <button
                  className={repmgrUnregisterClass}
                  style={{ marginRight: 5 }}
                  onClick={onConsoleAction.bind(null, host, 'repmgr_unregister')}
                >
                  Unregister
                </button>
              </div>
            </td>
          </tr>
          <tr>
            <td />
            <td>In recovery</td>
            <td>{backend.in_recovery && backend.in_recovery.toString()}</td>
            <td />
          </tr>
          <tr>
            <td>
              <StateStatus
                color={
                  backend.pgpool_status === 'up' || backend.pgpool_status === 'waiting'
                    ? 'green'
                    : 'red'
                }
              />
            </td>
            <td>PGPool status</td>
            <td>{backend.pgpool_status}</td>
            <td>
              <div className="btn-group" role="group" aria-label="pgpool actions">
                <button
                  className={pcpAttachClass}
                  style={{ marginRight: 5 }}
                  onClick={onConsoleAction.bind(null, host, 'pcp_attach')}
                >
                  Attach
                </button>
                <button
                  className={pcpDetachClass}
                  onClick={onConsoleAction.bind(null, host, 'pcp_detach')}
                >
                  Detach
                </button>
              </div>
            </td>
          </tr>
          <tr>
            <td />
            <td>PGPool role</td>
            <td>{backend.pgpool_role}</td>
            <td />
          </tr>
          <tr>
            <td />
            <td>PGPool rep. delay</td>
            <td>{backend.pgpool_replication_delay}</td>
            <td />
          </tr>
          <tr>
            <td colSpan={4}>
              <button
                className={recoveryNodeBtnClass}
                onClick={onConsoleAction.bind(null, host, 'pcp_recovery_node')}
              >
                Node recovery
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <Stats data={backend.data} />
    </div>
  );
};

class ReplicationStats extends Component {
  constructor(props) {
    super(props);
    this.renderContent = this.renderContent.bind(this);
    this.onConsoleAction = this.onConsoleAction.bind(this);
    this.onCloseConsole = this.onCloseConsole.bind(this);
    this.state = {
      console_action: null,
      pcp_node_id: null,
      host: null,
    };
  }

  componentDidMount() {
    this.props.fetchReplicationStats();
    this.interval = setInterval(this.props.fetchReplicationStats, 5000);
  }

  componentWillUnmount() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  onConsoleAction(host, action) {
    const node_info = this.props.replication_status[host];
    console.log(node_info);
    if (!this.state.console_action) {
      this.setState({
        console_action: action,
        pcp_node_id: node_info.pgpool_node_id,
        host,
      });
    }
  }

  onCloseConsole() {
    // console_action determines if the modal is showned or not
    this.setState({ console_action: null, pcp_node_id: null, host: null });
  }

  renderContent() {
    if (this.props.error) {
      return <div className="alert alert-danger">{this.props.error}</div>;
    }
    /*
		if (this.props.stats.length === 0){
			return (<div className="loader"></div>);
		}
		

		let content = this.props.stats.map((el,idx)=>{

			return(
				<Backend key={el.host} backend={el} />
			)
		});
		*/
    const content = [];

    const args = { pcp_node_id: this.state.pcp_node_id, host: this.state.host };
    let prompt;
    switch (this.state.console_action) {
      case 'pcp_detach':
        prompt = `detach node ${this.state.pcp_node_id} ?`;
        break;
      case 'pg_stop':
        const repl_node = this.props.repl_nodes.filter(el => el.node_name === this.state.host);
        console.log(repl_node);
        if (repl_node[0].type === 'primary') {
          prompt = `Stop active primary database on node ${
            this.state.pcp_node_id
          } ? !! It will cause a failover.`;
        } else {
          prompt = `Stop database on node ${this.state.pcp_node_id} ?`;
        }
        break;
      case 'pcp_recovery_node':
        prompt = `Perform node recovery of node ${this.state.pcp_node_id} ?`;
        break;
      default:
        prompt = null;
    }
    if (this.state.console_action) {
      content.push(
        <ShellConsoleModal
          key="console"
          action={this.state.console_action}
          modalActive={!!this.state.console_action}
          handleHideModal={this.onCloseConsole}
          onClose={this.onCloseConsole}
          onSuccess={this.onCloseConsole}
          args={args}
          prompt={prompt}
        />
      );
    }

    for (const e in this.props.replication_status) {
      if (this.props.replication_status.hasOwnProperty(e)) {
        content.push(
          <Backend
            key={e}
            host={e}
            backend={this.props.replication_status[e]}
            onConsoleAction={this.onConsoleAction}
          />
        );
      }
    }
    return content;
  }

  render() {
    return (
      <div className="panel panel-default">
        <div className="panel-heading">Replication Stats</div>

        <div className="panel-body">{this.renderContent()}</div>
      </div>
    );
  }
}

export default ReplicationStats;
