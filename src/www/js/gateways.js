/*

transitd web UI gateways js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

function clearGatewayList() {
	$("#gateways tbody").empty();
}

function insertGateway(name, ip, port, suite)
{
	var row = $( "<tr>"
				+"<td class='name'></td>"
				+"<td class='ip'></td>"
				+"<td class='port'></td>"
				+"<td class='suite'></td>"
				+"<td><button class='connect btn btn-primary' id='connect'>Connect</button></td>"
				+"</tr>");
	row.find(".name").text(name);
	row.find(".ip").text(ip);
	row.find(".port").text(port);
	row.find(".suite").text(suite);
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
			connectToGateway(ip, port, suite, function(){ });
		});
	}
	
	$("#gateways tbody").append(row);
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
					if(gateways == undefined || gateways.length == undefined || gateways.length==0)
						$('#gateways').hide();
					else
						$('#gateways').show();
					if(gateways)
						for (index = 0; index < gateways.length; ++index)
						{
							var gateway = gateways[index];
							insertGateway(gateway.name,
										  gateway.ip,
										  gateway.port,
										  gateway.suite);
						}
				}
				else
				{
					gatewaysTimeout = setTimeout(reloadGateways,5000);
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			gatewaysTimeout = setTimeout(reloadGateways,5000);
			return true;
		}
	});
	
}
