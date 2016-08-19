var service = new rpc.ServiceProxy("/jsonrpc", {methods: ['nodeInfo','connectTo','disconnect','listGateways','pollCallStatus','listSessions','startScan','getGraphSince','status']});

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

function bootstrap()
{
	if($("#gateways").length>0)
		reloadGateways();
	if($("#sessions").length>0)
		reloadSessions();
	if($("#status").length>0)
		reloadStatus();
	if($("#startScan").length>0)
		$("#startScan").click(startScan);
	if($("#network").length>0)
		startNetworkGraph();
}

var nodeInfo;
$(document).ready(function(){
	$("#gateways").hide();
	$("#sessions").hide();
	service.nodeInfo({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					nodeInfo = result;
					
					$(document).prop('title', nodeInfo.name);
					$('.navbar-brand').text(nodeInfo.name);
					
					if(nodeInfo.gateway || !nodeInfo.authorized)
					{
						$("#gateways").remove();
					}
					else
					{
						$("#gateways").show();
					}
					
					if(nodeInfo.authorized)
					{
						$("#sessions").show();
					}
					else
					{
						$("#sessions").remove();
					}
					
					bootstrap();
				}
				else
				{
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
});
