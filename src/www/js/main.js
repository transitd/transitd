var service = new rpc.ServiceProxy("/jsonrpc", {methods: ['connectTo','listGateways','pollCallStatus','listSessions','startScan','getGraphSince','status']});

function logAppendMessage(type, msg)
{
	if($("#log div").length >= 5)
		$("#log").children().first().remove();
	$("#log").append($("<div class='alert alert-"+type+"'\>").text(msg));
}

function nonBlockingCallWrapper(result, callback)
{
	if(result.callId)
	{
		var id = result.callId;
		setTimeout(function(){
			service.pollCallStatus({
				params: [id],
				onSuccess: function(result) {
					nonBlockingCallWrapper(result, callback);
				},
				onException: function(e) {
					logAppendMessage('danger', e);
					return true;
				}
			});
		},1000);
	}
	else
		callback(result);
}

$(document).ready(function(){
	if($("#gateways").length>0)
	{
		reloadGateways();
		setInterval(reloadGateways,5000);
	}
	if($("#sessions").length>0)
	{
		reloadSessions();
		setInterval(reloadSessions,5000);
	}
	if($("#status").length>0)
	{
		reloadStatus();
		setInterval(reloadStatus,5000);
	}
	if($("#startScan").length>0)
		$("#startScan").click(startScan);
	if($("#network").length>0)
		startNetworkGraph();
});
