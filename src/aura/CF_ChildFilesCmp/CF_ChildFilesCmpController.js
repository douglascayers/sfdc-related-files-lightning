/*
Author: Doug Ayers
Website: https://douglascayers.com
GitHub: https://github.com/DouglasCAyers/sfdc-related-files-lightning
License: BSD 3-Clause License
*/
({
    doInit : function( component, event, helper ) {

        var objectName = component.get( 'v.sObjectName' );
        var recordId = component.get( 'v.recordId' );

        Promise.all([
                helper.getRelatedFilesColumnsAsync( component ),        // FieldSetMember
                helper.getObjectDescribeAsync( component, objectName )  // DescribeSObjectResult
            ]).then( $A.getCallback( function( results ) {

                var fieldSetColumns = results[0];
                var objectDescribe = results[1];

                component.set( 'v.columns', helper.transformToDataTableColumns( fieldSetColumns ) );
                component.set( 'v.sObjectDescribe', objectDescribe );

                var selectedIndex = component.get( 'v.selectedIndex' );
                var filesAndNotesFilter = component.get( 'v.filesAndNotesFilter' );
                var childRelationshipNames = component.get( 'v.childRelationshipNames' );
                var childRelationshipFiles = [];

                // if specific list of relationship names are not provided
                // then use all available child relationships in object describe
                if ( $A.util.isEmpty( childRelationshipNames ) ) {
                    childRelationshipNames = helper.getChildRelationshipNamesSorted( component, objectDescribe );
                } else {
                    childRelationshipNames = childRelationshipNames.split( ',' );
                }

                if ( !$A.util.isEmpty( childRelationshipNames ) ) {

                    for ( var i = 0; i < childRelationshipNames.length; i++ ) {

                        var relationshipName = childRelationshipNames[i].trim().toUpperCase();
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

                return helper.loadAllChildRelationshipFilesAsync( component );

            })).catch( $A.getCallback( function( err ) {

                helper.toastMessage( 'Sorry, error initializing component', err, 'error' );

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

        helper.getRelatedFilesForIndexAsync( component, clickedIndex, false )
            .catch( $A.getCallback( function( err ) {

                helper.toastMessage( 'Sorry, error getting files', err, 'error' );

            }));

    },

    handleFileClick : function( component, event, helper ) {

        var clickedFileId = event.srcElement.getAttribute( 'data-fileId' );
        var fileIds = component.get( 'v.selectedFiles' ).map( function( file ) { return file.ContentDocumentId; } );

        helper.navigateToFiles( clickedFileId, fileIds );

    },

    handleUserClick : function( component, event, helper ) {

        var clickedUserId = event.srcElement.getAttribute( 'data-userId' );

        helper.navigateToRecord( clickedUserId );

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