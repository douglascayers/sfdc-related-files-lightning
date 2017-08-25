({
    getObjectDescribeAsync : function( component, objectName ) {

        var helper = this;

        return helper.enqueueAction( component, 'c.getObjectDescribe', {

            'myObjectName' : objectName

        }).then( $A.getCallback( function( objectDescribe ) {

            return objectDescribe;

        })).catch( $A.getCallback( function( errors ) {

            helper.logActionErrors( component, errors );

        }));

    },

    getRelatedFilesForIndexAsync : function( component, index, runInBackground ) {

        var helper = this;

        var recordId = component.get( 'v.recordId' );
        var objectDescribe = component.get( 'v.sObjectDescribe' );
        var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );

		var name = childRelationshipFiles[index].name;
        var objectName = objectDescribe.childRelationships[name].objectName;
        var fieldName = objectDescribe.childRelationships[name].fieldName;

        return helper.getRelatedFilesAsync( component, objectName, fieldName, recordId, runInBackground )
        	.then( $A.getCallback( function( response ) {

	            var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );
                var selectedIndex = component.get( 'v.selectedIndex' );

	            childRelationshipFiles[index].files = response.files;
                childRelationshipFiles[index].selected = ( selectedIndex == index );

    	        if ( selectedIndex == index ) {
	                component.set( 'v.selectedFiles', response.files );
	                component.set( 'v.selectedRelationship', childRelationshipFiles[selectedIndex] );
	            }

				component.set( 'v.childRelationshipFiles', childRelationshipFiles );

                return response;

        	}));

    },

    getRelatedFilesAsync : function( component, objectName, fieldName, fieldValue, background ) {

        var helper = this;

        return helper.enqueueAction( component, 'c.getRelatedFiles', {

            'objectName' : objectName,
            'fieldName' : fieldName,
            'fieldValue' : fieldValue

        }, {

            'background' : background,
            'storable' : true

        }).then( $A.getCallback( function( files ) {

            return {
                'files' : files
            };

        })).catch( $A.getCallback( function( errors ) {

            helper.logActionErrors( component, errors );

        }));

    },

    // -----------------------------------------------------------------

    showSpinner : function( component ) {

        $A.util.removeClass( component.find( 'spinner' ), 'slds-hide' );

    },

    hideSpinner : function( component ) {

        $A.util.addClass( component.find( 'spinner' ), 'slds-hide' );

    },

    navigateToRecord : function( recordId ) {

        console.log( 'navigating to record: ' + recordId );

        var event = $A.get( 'e.force:navigateToSObject' );

        if ( event ) {

            event.setParams({
                'recordId' : recordId
            }).fire();

        } else if ( ( typeof sforce !== 'undefined' ) && ( typeof sforce.one !== 'undefined' ) ) {

            sforce.one.navigateToSObject( recordId );

        } else {

            window.location.href = '/' + recordId;

        }

    },

    navigateToURL : function( url ) {

        console.log( 'navigating to url: ' + url );

        var event = $A.get( 'e.force:navigateToURL' );

        if ( event ) {

            event.setParams({
                'url' : url
            }).fire();

        } else if ( ( typeof sforce !== 'undefined' ) && ( typeof sforce.one !== 'undefined' ) ) {

            sforce.one.navigateToURL( url );

        } else {

            window.location.href = url;

        }

    },

    enqueueAction : function( component, actionName, params, options ) {

        var helper = this;

        var p = new Promise( function( resolve, reject ) {

            helper.showSpinner( component );

            var action = component.get( actionName );

            if ( params ) {
                action.setParams( params );
            }

            if ( options ) {
                if ( options.background ) { action.setBackground(); }
                if ( options.storable )   { action.setStorable(); }
            }

            action.setCallback( helper, function( response ) {

                helper.hideSpinner( component );

                if ( component.isValid() && response.getState() === 'SUCCESS' ) {

                    resolve( response.getReturnValue() );

                } else {

                    console.error( 'Error calling action "' + actionName + '" with state: ' + response.getState() );

                    reject( response.getError() );

                }
            });

            $A.enqueueAction( action );

        });

        return p;
    },

    logActionErrors : function( component, errors ) {
        if ( errors ) {
            if ( errors.length > 0 ) {
                for ( var i = 0; i < errors.length; i++ ) {
                    console.error( 'Error: ' + errors[i].message );
                }
            } else {
                console.error( 'Error: ' + errors );
            }
        } else {
            console.error( 'Unknown error' );
        }
    }
})