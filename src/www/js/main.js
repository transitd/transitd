/*

transitd web UI main js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

var service = new rpc.ServiceProxy("/jsonrpc", {methods: ['nodeInfo','connectTo','disconnect','listGateways','pollCallStatus','listSessions','startScan','getGraphSince','status']});

function logAppendMessage(type, msg)
{
	if($("#log div").length >= 5)
		$("#log").children().first().remove();
	var div = $("<div class='alert alert-"+type+" fade in'><a href='#' class='close' data-dismiss='alert' aria-label='close'>&times;</a><span class='logmsg'/></div>");
	div.find(".logmsg").text(msg);
	div.fadeIn(500).delay(10000).fadeOut(1000);
	$("#log").append(div);
}

function nonBlockingCallWrapper(result, callback)
{
	if(result.callId)
	{
		showSpinner();
		var id = result.callId;
		setTimeout(function(){
			service.pollCallStatus({
				params: [id],
				onSuccess: function(result) {
					hideSpinner();
					nonBlockingCallWrapper(result, callback);
				},
				onException: function(e) {
					hideSpinner();
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
	if($(".startScan").length>0)
		$(".startScan").click(startScan);
	if($("#network").length>0)
		startNetworkGraph();
}

var nodeInfo;
$(document).ready(function(){
	$("#gateways").hide();
	$("#sessions").hide();
	
	$(".navbar li.title").click(function(event) {
		event.preventDefault();
		$("#pageone-about").hide();
		$("#pageone-home").show();
		$(".navbar li.active").removeClass("active");
		$(".navbar li.home").addClass("active");
	});
	
	$(".navbar li.home").click(function(event) {
		event.preventDefault();
		$("#pageone-about").hide();
		$("#pageone-home").show();
		$(".navbar li.active").removeClass("active");
		$(".navbar li.home").addClass("active");
	});

	$(".navbar li.about").click(function(event) {
		event.preventDefault();
		$("#pageone-home").hide();
		$("#pageone-about").show();
		$(".navbar li.active").removeClass("active");
		$(".navbar li.about").addClass("active");
	});
	
	service.nodeInfo({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					nodeInfo = result;
					
					$(document).prop('title', nodeInfo.name);
					$('.navbar-brand').text(nodeInfo.name);
					
					if(nodeInfo.gateway)
					{
						$('.gateway-hidden').addClass('hidden');
						$('.subscriber-hidden').removeClass('hidden');
					}
					else
					{
						$('.subscriber-hidden').addClass('hidden');
						$('.gateway-hidden').removeClass('hidden');
					}
					
					if(nodeInfo.authorized)
					{
						$('.authorized-hidden').addClass('hidden');
						$('.unauthorized-hidden').removeClass('hidden');
					}
					else
					{
						$('.unauthorized-hidden').addClass('hidden');
						$('.authorized-hidden').removeClass('hidden');
					}
					
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

var spinnerCount = 0;
function showSpinner()
{
	if(spinnerCount==0)
		$("#spinner").show();
	spinnerCount++;
}
function hideSpinner()
{
	spinnerCount--;
	if(spinnerCount==0)
		$("#spinner").hide();
}
