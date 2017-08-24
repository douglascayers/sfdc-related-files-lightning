({
    doInit : function( component, event, helper ) {

        var objectName = component.get( 'v.sObjectName' );
        var recordId = component.get( 'v.recordId' );

        helper.getObjectDescribeAsync( component, objectName )
            .then( $A.getCallback( function( objectDescribe ) {

                component.set( 'v.sObjectDescribe', objectDescribe );

                var selectedIndex = component.get( 'v.selectedIndex' );
                var childRelationshipNames = component.get( 'v.childRelationshipNames' );
                var childRelationshipFiles = [];

                if ( $A.util.isEmpty( childRelationshipNames ) ) {

                    childRelationshipNames = [];
                    for ( var relationshipName in objectDescribe.childRelationships ) {
                        childRelationshipNames.push( relationshipName );
                    }
                    childRelationshipNames.sort();

                } else {

                    childRelationshipNames = childRelationshipNames.split( ',' );

                }

                if ( !$A.util.isEmpty( childRelationshipNames ) ) {

                    for ( var i = 0; i < childRelationshipNames.length; i++ ) {

                        var relationshipName = childRelationshipNames[i].trim();

                        childRelationshipFiles[i] = {
                            'name' : relationshipName,
                            'describe' : objectDescribe.childRelationships[relationshipName],
                            'selected' : ( i == selectedIndex ),
                            'files' : []
                        };

                    }

                }

                component.set( 'v.childRelationshipFiles', childRelationshipFiles );

                // TODO how to do these separately rather than get boxcarred together?
                for ( var i = 0; i < childRelationshipFiles.length; i++ ) {
                	helper.getRelatedFilesForIndexAsync( component, i );
                }

            }));

    },

    handleChildRelationshipClick : function( component, event, helper ) {

		var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );
        var selectedIndex = component.get( 'v.selectedIndex' );
        var clickedIndex = event.srcElement.getAttribute( 'data-index' );

        childRelationshipFiles[selectedIndex].selected = false;
        childRelationshipFiles[clickedIndex].selected = true;

        component.set( 'v.selectedFiles', childRelationshipFiles[clickedIndex].files );
        component.set( 'v.childRelationshipFiles', childRelationshipFiles );
        component.set( 'v.selectedIndex', clickedIndex );

        helper.getRelatedFilesForIndexAsync( component, clickedIndex );

    },

    handleFileClick : function( component, event, helper ) {

        var clickedFileId = event.srcElement.getAttribute( 'data-fileId' );

		$A.get( 'e.lightning:openFiles' ).fire({
            recordIds : component.get( 'v.selectedFiles' ).map( function( file ) { return file.ContentDocumentId; } ),
            selectedRecordId : clickedFileId
    	});

    }
})