var service = new rpc.ServiceProxy("/jsonrpc", {methods: ['connectTo','listGateways','pollCallStatus']});

function logAppendMessage(type, msg)
{
    if($("#log div").length >= 10)
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

function connectTo(ip, port, method)
{
    service.connectTo({
        params: [ip, port, method],
        onSuccess: function(result) {
            nonBlockingCallWrapper(result, function(result) {
                if(result.success==true)
                {
                    var message = "Connected!\n";
                    if(result.ipv4)
                        message += "IPv4: "+result.ipv4+"\n";
                    if(result.ipv6)
                        message += "IPv6: "+result.ipv6+"\n";
                    message += "Timeout: "+result.timeout+"\n";
                    logAppendMessage('success', message);
                    
                    reloadGateways();
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

function insertGateway(name, ip, port, method) {
    var row = $("<tr><td class='name'></td><td class='ip'></td><td class='port'></td><td class='method'></td><td><button class='connect'>connect</button></td></tr>");
    row.find(".name").text(name);
    row.find(".ip").text(ip);
    row.find(".port").text(port);
    row.find(".method").text(method);
    row.find(".connect").click(function(e){
        e.preventDefault();
        connectTo(ip, port, method);
    });
    $("#gateways").append(row);
}

function clearGatewayList() {
    $("#gateways").empty();
}

function reloadGateways()
{
    service.listGateways({
        params: [],
        onSuccess: function(result) {
            nonBlockingCallWrapper(result, function(result) {
                if(result.success==true)
                {
                    var gateways = result.gateways;
                    clearGatewayList();
                    for (index = 0; index < gateways.length; ++index)
                    {
                        var gateway = gateways[index];
                        insertGateway(gateway.name, gateway.ip, gateway.port, gateway.method);
                    }
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

$(document).ready(function(){
    if($("#gateways").length>0)
    {
        reloadGateways();
        setInterval(reloadGateways,3000);
    }
    
    
});

