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

                if ( !$A.util.isUndefinedOrNull( childRelationshipNames ) ) {

                    var names = childRelationshipNames.split(',');

                    for ( var i = 0; i < names.length; i++ ) {

                        var name = names[i].trim();

                        childRelationshipFiles[i] = {
                            'name' : name,
                            'selected' : ( i == selectedIndex ),
                            'files' : []
                        };

                    }

                }
                
                component.set( 'v.childRelationshipFiles', childRelationshipFiles );

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