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

                    var childRelationships = [];

                    for ( var relationshipName in objectDescribe.childRelationships ) {
                        childRelationships.push( objectDescribe.childRelationships[relationshipName] );
                    }

                    childRelationships.sort( function( a, b ) {
                        if ( a.objectLabelPlural.toUpperCase() < b.objectLabelPlural.toUpperCase() ) {
                            return -1;
                        } else if ( a.objectLabelPlural.toUpperCase() > b.objectLabelPlural.toUpperCase() ) {
                            return 1;
                        } else {
                            return 0;
                        }
                    });

                    childRelationshipNames = childRelationships.map( function( childRelationship ) {
                        return childRelationship.relationshipName;
                    });

                } else {

                    childRelationshipNames = childRelationshipNames.split( ',' );

                }

                if ( !$A.util.isEmpty( childRelationshipNames ) ) {

                    for ( var i = 0; i < childRelationshipNames.length; i++ ) {

                        var relationshipName = childRelationshipNames[i].trim();
                        var isSelected = ( i == selectedIndex );

                        childRelationshipFiles[i] = {
                            'name' : relationshipName,
                            'describe' : objectDescribe.childRelationships[relationshipName],
                            'selected' : isSelected,
                            'files' : null
                        };

                        if ( isSelected ) {
                            component.set( 'v.selectedRelationship', childRelationshipFiles[i] );
                        }

                    }

                }

                component.set( 'v.childRelationshipFiles', childRelationshipFiles );

                for ( var i = 0; i < childRelationshipFiles.length; i++ ) {
                	helper.getRelatedFilesForIndexAsync( component, i, true );
                }

            }));

    },

    handleChildRelationshipClick : function( component, event, helper ) {

		var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );
        var selectedIndex = component.get( 'v.selectedIndex' );
        var clickedIndex = event.currentTarget.getAttribute( 'data-index' );

        childRelationshipFiles[selectedIndex].selected = false;
        childRelationshipFiles[clickedIndex].selected = true;

        component.set( 'v.selectedFiles', childRelationshipFiles[clickedIndex].files );
        component.set( 'v.childRelationshipFiles', childRelationshipFiles );
        component.set( 'v.selectedIndex', clickedIndex );
        component.set( 'v.selectedRelationship', childRelationshipFiles[clickedIndex] );

        helper.getRelatedFilesForIndexAsync( component, clickedIndex, false );

    },

    handleFileClick : function( component, event, helper ) {

        var clickedFileId = event.srcElement.getAttribute( 'data-fileId' );

		$A.get( 'e.lightning:openFiles' ).fire({
            recordIds : component.get( 'v.selectedFiles' ).map( function( file ) { return file.ContentDocumentId; } ),
            selectedRecordId : clickedFileId
    	});

    },

    handleUserClick : function( component, event, helper ) {

        var clickedUserId = event.srcElement.getAttribute( 'data-userId' );

        helper.navigateToRecord( clickedUserId );

    }
})