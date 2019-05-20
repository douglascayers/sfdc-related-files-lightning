/*
Author: Doug Ayers
Website: https://douglascayers.com
GitHub: https://github.com/DouglasCAyers/sfdc-related-files-lightning
License: BSD 3-Clause License
*/
({
    getObjectDescribeAsync : function( component, objectName ) {

        var helper = this;

        return helper.enqueueAction( component, 'c.getObjectDescribe', {

            'myObjectName' : objectName

        }).then( $A.getCallback( function( objectDescribe ) {

            return objectDescribe;

        }));

    },

    loadAllChildRelationshipFilesAsync : function( component ) {

        $A.util.removeClass( component.find( 'init-spinner' ), 'slds-hide' );

        var helper = this;

        var promises = [];
        var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );

        for ( var i = 0; i < childRelationshipFiles.length; i++ ) {
            promises.push( helper.getRelatedFilesForIndexAsync( component, i, true ) );
        }

        return Promise.all( promises )
            .then( function() {
                $A.util.addClass( component.find( 'init-spinner' ), 'slds-hide' );
            });

    },

    getRelatedFilesForIndexAsync : function( component, index, runInBackground ) {

        var helper = this;

        var recordId = component.get( 'v.recordId' );
        var objectDescribe = component.get( 'v.sObjectDescribe' );
        var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );
        var filesAndNotesFilter = component.get( 'v.filesAndNotesFilter' );
        var fieldSetName = component.get( 'v.fieldSetName' );

        var relationshipName = childRelationshipFiles[index].name;
        var objectName = objectDescribe.childRelationships[relationshipName].objectName;
        var fieldName = objectDescribe.childRelationships[relationshipName].fieldName;

        return helper.getRelatedFilesAsync( component, relationshipName, objectName, fieldName, recordId, filesAndNotesFilter, fieldSetName, runInBackground )
            .then( $A.getCallback( function( response ) {

                var childRelationshipFiles = component.get( 'v.childRelationshipFiles' );
                var selectedIndex = component.get( 'v.selectedIndex' );

                helper.applyFileTypeIconNames( component, response.files );

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

    getRelatedFilesAsync : function( component, relationshipName, objectName, fieldName, fieldValue, filesAndNotesFilter, fieldSetName, background ) {

        var helper = this;

        return helper.enqueueAction( component, 'c.getRelatedFiles', {

            'relationshipName' : relationshipName,
            'objectName' : objectName,
            'fieldName' : fieldName,
            'fieldValue' : fieldValue,
            'filesAndNotesFilter' : filesAndNotesFilter,
            'fieldSetName' : fieldSetName

        }, {

            'background' : background

        }).then( $A.getCallback( function( files ) {

            return {
                'files' : files
            };

        }));

    },

    getRelatedFilesColumnsAsync : function( component, fieldSetName ) {

        var helper = this;

        return helper.enqueueAction( component, 'c.getRelatedFilesColumns', {

            'fieldSetName' : fieldSetName

        });

    },

    getChildRelationshipNamesSorted : function( component, objectDescribe ) {

        var childRelationships = [];

        for ( var relationshipName in objectDescribe.childRelationships ) {
            childRelationships.push( objectDescribe.childRelationships[relationshipName] );
        }

        childRelationships.sort( function( a, b ) {
            if ( a.relationshipLabel.toUpperCase() < b.relationshipLabel.toUpperCase() ) {
                return -1;
            } else if ( a.relationshipLabel.toUpperCase() > b.relationshipLabel.toUpperCase() ) {
                return 1;
            } else {
                return 0;
            }
        });

        var childRelationshipNames = childRelationships.map( function( childRelationship ) {
            return childRelationship.relationshipName;
        });

        return childRelationshipNames;
    },

    applyFileTypeIconNames : function( component, files ) {

        for ( var i = 0; i < files.length; i++ ) {

            var iconName = 'doctype:attachment';
            var file = files[i];

            if ( /^POWER_POINT/i.test( file.FileType ) ) {
                iconName = 'doctype:ppt';
            }
            else if ( /^EXCEL/i.test( file.FileType ) ) {
                iconName = 'doctype:excel';
            }
            else if ( /^WORD/i.test( file.FileType ) ) {
                iconName = 'doctype:word';
            }
            else if ( /^(MP3|WAV|M4A)/i.test( file.FileType ) ) {
                iconName = 'doctype:audio';
            }
            else if ( /^MP4/i.test( file.FileType ) ) {
                iconName = 'doctype:mp4';
            }
            else if ( /^CSV/i.test( file.FileType ) ) {
                iconName = 'doctype:csv';
            }
            else if ( /^TEXT/i.test( file.FileType ) ) {
                iconName = 'doctype:txt';
            }
            else if ( /^PDF/i.test( file.FileType ) ) {
                iconName = 'doctype:pdf';
            }
            else if ( /^XML/i.test( file.FileType ) ) {
                iconName = 'doctype:xml';
            }
            else if ( /^ZIP/i.test( file.FileType ) ) {
                iconName = 'doctype:zip';
            }
            else if ( /^(PNG|GIF|JPG|JPEG|TIFF|BMP)/i.test( file.FileType ) ) {
                iconName = 'doctype:image';
            }
            else if ( /^PACK/i.test( file.FileType ) ) {
                iconName = 'doctype:pack';
            }
            else if ( /^(MOV|WMV|M4V)/i.test( file.FileType ) ) {
                iconName = 'doctype:movie';
            }
            else if ( /^LINK/i.test( file.FileType ) ) {
                iconName = 'doctype:link';
            }
            else if ( /^HTML/i.test( file.FileType ) ) {
                iconName = 'doctype:html';
            }
            else if ( /^SNOTE/i.test( file.FileType ) ) {
                iconName = 'doctype:stypi';
            }

            file.FileTypeIconName = iconName;

        }

    },

    transformToDataTableColumns : function( fieldSetColumns ) {

        return fieldSetColumns.map( function( fieldSetColumn ) {

            var dataTableColumn = Object.assign( {}, fieldSetColumn );

            dataTableColumn.cellAttributes = dataTableColumn.cellAttributes || {};
            dataTableColumn.typeAttributes = dataTableColumn.typeAttributes || {};

            switch ( fieldSetColumn.type.toUpperCase() ) {

                case 'BOOLEAN':
                    dataTableColumn.type = 'boolean';
                    break;

                case 'CURRENCY':
                    dataTableColumn.type = 'currency';
                    dataTableColumn.cellAttributes.alignment = 'right';
                    break;

                case 'DOUBLE':
                case 'INTEGER':
                case 'LONG':
                    dataTableColumn.type = 'number';
                    dataTableColumn.cellAttributes.alignment = 'right';
                    break;

                case 'PERCENT':
                    dataTableColumn.type = 'percent';
                    dataTableColumn.cellAttributes.alignment = 'right';
                    break;

                case 'STRING':
                case 'COMBOBOX':
                case 'PICKLIST':
                case 'MULTIPICKLIST':
                case 'TEXTAREA':
                case 'ENCRYPTEDSTRING':
                    dataTableColumn.type = 'text';
                    break;

                case 'PHONE':
                    dataTableColumn.type = 'phone';
                    break;

                case 'DATE':
                    dataTableColumn.type = 'date-local';
                    break;

                case 'DATETIME':
                    dataTableColumn.type = 'date';
                    dataTableColumn.typeAttributes.year = 'numeric';
                    dataTableColumn.typeAttributes.month = '2-digit';
                    dataTableColumn.typeAttributes.day = '2-digit';
                    dataTableColumn.typeAttributes.hour = '2-digit';
                    dataTableColumn.typeAttributes.minute = '2-digit';
                    break;

                case 'TIME':
                    dataTableColumn.type = 'date';
                    dataTableColumn.typeAttributes.hour = '2-digit';
                    dataTableColumn.typeAttributes.minute = '2-digit';
                    break;

                case 'ID':
                case 'REFERENCE':
                    var origFieldName = dataTableColumn.fieldName;
                    var pathToNameField = (
                        origFieldName.endsWith( 'Id' ) ? origFieldName.slice( 0, -2 ) :
                        origFieldName.endsWith( '__c' ) ? origFieldName.replace( '__c', '__r' ) : ''
                    ) + 'Name';
                    dataTableColumn.fieldName = 'LinkTo' + origFieldName;
                    dataTableColumn.type = 'url';
                    dataTableColumn.typeAttributes = Object.assign({
                        'label' : {
                            'fieldName' : pathToNameField
                        },
                        'tooltip' : {
                            'fieldName' : pathToNameField
                        },
                        'target' : '_blank'
                    }, dataTableColumn.typeAttributes );
                    break;

                case 'URL':
                    dataTableColumn.type = 'url';
                    break;

                case 'EMAIL':
                    dataTableColumn.type = 'email';
                    break;

            }

            if ( dataTableColumn.fieldName === 'Title' ) {

                dataTableColumn.fieldName = 'LinkToContentDocumentId';
                dataTableColumn.type = 'url';

                dataTableColumn.typeAttributes = Object.assign({
                    'label' : {
                        'fieldName' : 'Title'
                    },
                    'tooltip' : {
                        'fieldName' : 'Title'
                    },
                    'target' : '_blank'
                }, dataTableColumn.typeAttributes );

                dataTableColumn.cellAttributes = Object.assign({
                    'iconName' : {
                        'fieldName' : 'FileTypeIconName'
                    }
                }, dataTableColumn.cellAttributes );

            }

            if ( dataTableColumn.fieldName === 'ContentSize' ) {

                dataTableColumn.fieldName = 'HumanReadableContentSize';
                dataTableColumn.type = 'text';
                dataTableColumn.typeAttributes = {}; // unset
                dataTableColumn.cellAttributes = {}; // unset

            }

            return dataTableColumn;
        });
    },

    // -----------------------------------------------------------------

    showSpinner : function( component ) {

        $A.util.removeClass( component.find( 'spinner' ), 'slds-hide' );

    },

    hideSpinner : function( component ) {

        $A.util.addClass( component.find( 'spinner' ), 'slds-hide' );

    },

    toastMessage : function( title, message, type ) {

        // https://developer.salesforce.com/docs/atlas.en-us.lightning.meta/lightning/ref_force_showToast.htm

        var helper = this;

        // convenience so code can toast errors without
        // themselves figuring out how to get the real message from them
        if ( message instanceof Error ) {
            message = helper.unwrapAuraErrorMessage( message );
        }

        $A.get( 'e.force:showToast' ).setParams({
            title : ( title || 'Message' ),
            message : ( message || '' ),
            type : ( type || 'info' )
        }).fire();

    },

    navigateToFiles : function( selectedFileId, fileIds ) {

        var helper = this;

        var event = $A.get( 'e.lightning:openFiles' );

        if ( event ) {

            event.fire({
                recordIds : fileIds,
                selectedRecordId : selectedFileId
            });

        } else {

            helper.navigateToRecord( selectedFileId );

        }

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

                    helper.logActionErrors( response.getError() );

                    reject( helper.getMessageFromActionResponseError( response.getError() ) );

                }
            });

            $A.enqueueAction( action );

        });

        return p;
    },

    logActionErrors : function( errors ) {
        if ( errors ) {
            if ( errors.length > 0 ) {
                for ( var i = 0; i < errors.length; i++ ) {
                    console.error( 'Error: ' + errors[i].message );
                }
            } else {
                console.error( 'Error: ' + ( errors.message || errors ) );
            }
        } else {
            console.error( 'Unknown error' );
        }
    },

    getMessageFromActionResponseError : function( errors ) {
        var text = '';
        if ( errors ) {
            if ( errors.length > 0 ) {
                for ( var i = 0; i < errors.length; i++ ) {
                    text += '\n' + errors[i].message;
                }
            } else {
                text = ( errors.message || errors );
            }
        }
        return text;
    },

    /**
     * When using $A.getCallback() function, if an error is thrown
     * then it wraps the error in an AuraError. The AuraError, unfortunately,
     * has a new message property whose value is "Error in $A.getCallback[YOUR_ORIGINAL_ERROR_MESSAGE]".
     * The only way to obtain YOUR_ORIGINAL_ERROR_MESSAGE is to substring
     * the AuraError text out of its message.
     */
    unwrapAuraErrorMessage : function( err ) {

        var message = err.message;

        var startStr = 'Error in $A.getCallback() [';
        var endStr = ']';

        var startIdx = err.message.indexOf( startStr );
        var endIdx = err.message.lastIndexOf( endStr );

        if ( startIdx >= 0 && endIdx >= 0 ) {
            message = err.message.substring( startIdx + startStr.length, endIdx );
        }

        return message;
    }
})
/*
BSD 3-Clause License

Copyright (c) 2019, Doug Ayers
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/