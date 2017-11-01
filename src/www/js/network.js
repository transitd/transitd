/*

transitd web UI network graph js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

function startScan()
{
	service.startScan({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					logAppendMessage('success', "Scan started");
					loadNetworkGraph();
				}
				else
					logAppendMessage('danger', result.errorMsg);
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
}

var edges, nodes, network, sinceTimestamp = 0, lastScanId = 0;

function startNetworkGraph()
{
	nodes = new vis.DataSet();
	edges = new vis.DataSet();
	var container = document.getElementById('network');
	
	var options = {
		physics: { maxVelocity: 50, solver: 'repulsion' },
		groups: {
		  self: {
			color: 'blue',
			shape: 'dot',
			size: 15,
			font:{ size: 14 },
		  },
		  none: {
			color: 'gray',
			shape: 'dot',
			size: 10,
			font:{ size: 8 },
		  },
		  node: {
			color: 'red',
			shape: 'dot',
			size: 11,
			font:{ size: 12 },
		  },
		  gateway: {
			color: 'green',
			shape: 'dot',
			size: 12,
			font:{ size: 12 },
		  }
		}
	  };
	
	network = new vis.Network(container, { 'nodes': nodes, 'edges': edges }, options);
	
	loadNetworkGraph();
	setInterval(loadNetworkGraph,5000);
}

function addNode(id, label, group)
{
	if(nodes.get(id) == null)
		nodes.add({'id': id, 'label': label, 'group': group});
	if(group == 'self')
		network.focus(id, { locked: true });
}


function addLink(id1, id2)
{
	if(edges.get(id1+'-'+id2) == null)
		edges.add({id:id1+'-'+id2, from: id1, to: id2});
}

var networkGraphTimeout;

function loadNetworkGraph()
{
	if(networkGraphTimeout)
		clearTimeout(networkGraphTimeout);
	service.getGraphSince({
		params: [sinceTimestamp],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				networkGraphTimeout = setTimeout(loadNetworkGraph,5000);
				if(result.success==true)
				{
					sinceTimestamp = Math.floor(Date.now() / 1000);
					
					if(result.scanId != lastScanId)
					{
						 nodes.clear();
						 edges.clear();
					}
					if(result.hosts)
						for (index = 0; index < result.hosts.length; ++index)
						{
							var host = result.hosts[index];
							addNode(host.ip, host.label, host.type);
						}
					
					if(result.links)
						for (index = 0; index < result.links.length; ++index)
						{
							var link = result.links[index];
							addLink(link.ip1, link.ip2);
						}
					
					lastScanId = result.scanId;
				}
				else
				{
					networkGraphTimeout = setTimeout(loadNetworkGraph,5000);
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			networkGraphTimeout = setTimeout(loadNetworkGraph,5000);
			return true;
		}
	});
}