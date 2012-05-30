var Via_X = viaLonlat.lon.toFixed(7);
var Via_Y = viaLonlat.lat.toFixed(7);
via_xml = via_xml + '<xls:ViaPoint><xls:Position><gml:Point><gml:pos>'+Via_X+' '+Via_Y+'</gml:pos></gml:Point></xls:Position></xls:ViaPoint>';
}
var data = 'Start='+Start_X+','+Start_Y+'&End='+End_X+','+End_Y+ '&Via='+ via_xml +'&lang=de&distunit=KM&routepref='
    +routepref+'&avoidAreas=&useTMC=false&noMotorways='+noMotorways+'&instructions=false';
var url = 'php/OpenLSRS_DetermineRoute.php';
//new RouteSummary not calculated yet
document.getElementById('informations').innerHTML = '<table><tr><td><span class="route_summary_heading">Route changed ...</span></td></tr><tr><td><span class="infos">Please press <b>"Calculate"</b> to show the new RouteSummary!'+
    '<br><br><b>Notice:</b> AvoidAreas are not work in the Location-Dragging-Mode <br> and it is NOT possible to drag ViaPoints yet!</span></td></tr></table>';
// assuming you already know how to create your handler
//var request = OpenLayers.Request.POST({url: url,data: data,callback: showRoute});
new OpenLayers.Ajax.Request(url,
    { method: 'post',
        parameters: data,
        onComplete: showRouteGeom
    }
);
}
function showRoute(response) {
// alert(response.responseText);
    if (response) {
// remove route, start and end
//vectorLayerStart.destroyFeatures();
//vectorLayerEnd.destroyFeatures();
        vectorLayerRoute.removeFeatures(vectorLayerRoute.features);
//alert(response.responseText);
        var xmlresponse = response.responseXML;
        var errorList = xmlresponse.getElementsByTagName('ErrorList');
        if(errorList.length == 0)//IEHack
            errorList = xmlresponse.getElementsByTagName('xls:ErrorList');
        if(errorList.length > 0){
            var error = errorList[0].getElementsByTagName('Error');
            if(error.length == 0)//IEHack
                error = xmlresponse.getElementsByTagName('xls:Error');
            var message = error[0].getAttribute('message')
            alert('Message: '+message+'\nNotice: the Route Service is at this time only for Europe!');
//document.getElementById('problems').innerHTML = '<span class="problems">'+message+'</span>';
            document.getElementById('informations').innerHTML = "";
        }
        else{
// parse RouteGeometry
            var routeGeometry = xmlresponse.getElementsByTagName('RouteGeometry');
            if(routeGeometry.length == 0)//IE Hack
                routeGeometry = xmlresponse.getElementsByTagName('xls:RouteGeometry');
//alert('Positions: '+positions.length);
            var positions = routeGeometry[0].getElementsByTagName('pos');
            if(positions.length == 0)//IEHack
                positions = routeGeometry[0].getElementsByTagName('gml:pos');
            var startPos, endPos;
            var line_points = [];
            var lonlat4gpx = '';
            lonlatRoute = '';
            lonlatBuffer = ''; // global variable for buffer calculation
            for (var i = 0; i < positions.length; i++) {
                var pos;
                if(typeof positions[i].textContent != 'undefined')
                    pos = positions[i].textContent.split(' ');
                else
                    pos = positions[i].text.split(' ');
                lonlat4gpx += ' <trkpt lon="'+pos[0]+'" lat="'+pos[1]+'"/>\n';
//7.10807 50.735097,7.108069921645446 50.73509695251465,7.1079199 50.7353445,7.10
                if(lonlatRoute.length > 0){
                    lonlatRoute +=','+pos[0]+' '+pos[1];
                    lonlatBuffer +=' '+pos[0]+' '+pos[1];
                }
                else{
                    lonlatRoute +=pos[0]+' '+pos[1];
                    lonlatBuffer +=pos[0]+' '+pos[1];
                }
                line_points.push(new OpenLayers.Geometry.Point(pos[0],pos[1]).transform(new OpenLayers.Projection("EPSG:4326"), new OpenLayers.Projection("EPSG:900913")) );
                if(i % 100 == 0 && i>0 || i==positions.length-1){
                    vectorLayerRoute.addFeatures([new OpenLayers.Feature.Vector(new OpenLayers.Geometry.LineString(line_points))]);
                    line_points = [];
                    line_points.push(new OpenLayers.Geometry.Point(pos[0],pos[1]).transform(new OpenLayers.Projection("EPSG:4326"), new OpenLayers.Projection("EPSG:900913")) );
                }
                if(i==0)
                    startPos = pos;
                if(i==positions.length-1)
                    endPos = pos;
            }
            rbufferdata = 'RouteCoords='+lonlatBuffer;
// var bufferurl = 'php/WPS_Buffer.php';
//
//// alert(bufferdata);
// new OpenLayers.Ajax.Request(bufferurl,
// { method: 'post',
// parameters: rbufferdata,
