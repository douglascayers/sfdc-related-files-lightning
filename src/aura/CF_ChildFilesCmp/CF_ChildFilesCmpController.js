({
    doInit : function( component, event, helper ) {

        // TODO remove
        component.set( 'v.selectedFiles', [ { 'Title' : 'hello.txt', 'Owner' : 'Doug Ayers' }]);

        var objectName = component.get( 'v.sObjectName' );
        var recordId = component.get( 'v.recordId' );

        helper.getObjectDescribeAsync( component, objectName )
            .then( $A.getCallback( function( objectDescribe ) {

                component.set( 'v.sObjectDescribe', objectDescribe );

                var childRelationshipNames = component.get( 'v.childRelationshipNames' );
                var childRelationshipFiles = [];

                if ( !$A.util.isUndefinedOrNull( childRelationshipNames ) ) {

                    var names = childRelationshipNames.split(',');

                    for ( var i = 0; i < names.length; i++ ) {

                        var name = names[i].trim();

                        childRelationshipFiles[i] = {
                            'name' : name,
                            'files' : []
                        };

                        helper.getRelatedFilesAsync(
                            component,
                            i,
                            objectDescribe.childRelationships[name].objectName,
                            objectDescribe.childRelationships[name].fieldName,
                            recordId )
                            .then( $A.getCallback( function( response ) {

                                var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );

                                childRelationshipFiles[response.index].files = response.files;

                                component.set( 'v.childRelationshipFiles', childRelationshipFiles );

                            }));

                    }

                }

                component.set( 'v.childRelationshipFiles', childRelationshipFiles );

            }));

    }
})