function clearGatewayList() {
	$("#gateways").empty();
}

function insertGateway(name, ip, port, method)
{
	var row = $( "<tr>"
				+"<td class='name'></td>"
				+"<td class='ip'></td>"
				+"<td class='port'></td>"
				+"<td class='method'></td>"
				+"<td><button class='connect' id='connect'>Connect</button></td>"
				+"</tr>");
	row.find(".name").text(name);
	row.find(".ip").text(ip);
	row.find(".port").text(port);
	row.find(".method").text(method);
	var session;
	jQuery.each(activeSessions, function(i, s){
		if(s.meshIP==ip)
			session = s;
	});
	if(session)
		row.find(".connect").hide();
	else
	{
		row.find(".connect").click(function(e) {
			e.preventDefault();
			$(this).hide();
			connectTo(ip, port, method, function(){

			});
		});
	}
	
	$("#gateways").append(row);
}

var gatewaysTimeout;

function reloadGateways()
{
	if(gatewaysTimeout)
		clearTimeout(gatewaysTimeout);
	service.listGateways({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				clearGatewayList();
				gatewaysTimeout = setTimeout(reloadGateways,5000);
				if(result.success==true)
				{
					var gateways = result.gateways;
					for (index = 0; index < gateways.length; ++index)
					{
						var gateway = gateways[index];
						insertGateway(gateway.name,
									  gateway.ip,
									  gateway.port,
									  gateway.method);
					}
				}
				else
					logAppendMessage('danger', result.errorMsg);
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			gatewaysTimeout = setTimeout(reloadGateways,5000);
			return true;
		}
	});
	
}
