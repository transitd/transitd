/*

transitd web UI main js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

var serviceProxy = new rpc.ServiceProxy("/jsonrpc", {methods: ['nodeInfo','connect','disconnect','listGateways','pollCallStatus','listSessions','startScan','getGraphSince','status','configure']});
var restarting = false;

// proxy that wraps calls with showSpinner/hideSpinner pair
var service = new Proxy(serviceProxy, {
	get: function(target, name) {
		return function() {
			
			// manage spinner
			showSpinner();
			if(arguments[0])
			{
				var onSuccess = arguments[0].onSuccess;
				var onException = arguments[0].onException;
				arguments[0].onSuccess = function(a) { var retval; if(onSuccess) retval = onSuccess(a); hideSpinner(); return retval; }
				arguments[0].onException = function(a) { var retval; if(onException) retval = onException(a); hideSpinner(); return retval; }
			}
			
			// don't do anything if waiting for a restart
			if(restarting)
				return null;
			
			// run service proxy function
			var retval = target[name].apply(this, arguments);
			return retval;
		}
	}
});

function logAppendMessage(type, msg)
{
	if($("#log div").length >= 5)
		$("#log").children().first().remove();
	var div = $("<div class='alert alert-"+type+" fade in'><a href='#' class='close' data-dismiss='alert' aria-label='close'>&times;</a><span class='logmsg'/></div>");
	div.find(".logmsg").text(msg);
	div.fadeIn(500).delay(10000).fadeOut(1000);
	$("#log").append(div);
}

function nonBlockingCallWrapper(result, callback, timeout)
{
	timeout = timeout | 100;
	
	if(result.callId)
	{
		showSpinner();
		var id = result.callId;
		setTimeout(function(){
			service.pollCallStatus({
				params: [id],
				onSuccess: function(result) {
					hideSpinner();
					nonBlockingCallWrapper(result, callback, timeout*2);
				},
				onException: function(e) {
					hideSpinner();
					logAppendMessage('danger', e);
					return true;
				}
			});
		},timeout);
	}
	else
		callback(result);
}

function bootstrap()
{
	$(document).prop('title', nodeInfo.name);
	$('.node-name').text(nodeInfo.name);
	
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
		$("#gateways").remove();
	else
		$("#gateways").show();
	
	if(nodeInfo.authorized)
		$("#sessions").show();
	else
		$("#sessions").remove();
	
	if(nodeInfo.config)
		initConfiguration(nodeInfo.config);
	
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

function gotopage(page)
{
	$(".container.onepage").addClass('hidden');
	$(".container#onepage-"+page).removeClass('hidden');
	$(".navbar li.active").removeClass('active')
	$("li.onepage-"+page).addClass('active')
}

var nodeInfo;
$(document).ready(function(){
	$("#gateways").hide();
	$("#sessions").hide();
	
	$("a[onepage]").click(function(e){
		e.preventDefault();
		gotopage($(this).attr("onepage"));
	});
	
	service.nodeInfo({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					nodeInfo = result;
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
	if(spinnerCount>=0)
		$("#spinner").show();
	spinnerCount++;
}
function hideSpinner()
{
	spinnerCount--;
	if(spinnerCount<=0)
		$("#spinner").hide();
}
