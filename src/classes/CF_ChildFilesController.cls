/*
Author: Doug Ayers
Website: https://douglascayers.com
GitHub: https://github.com/DouglasCAyers/sfdc-related-files-lightning
License: BSD 3-Clause License
*/
public with sharing class CF_ChildFilesController {

    public ID recordId { get; set; }

    public String sObjectName { get; set; }

    public SObject record { get; set; }

    public String nameField { get; set; }

    public CF_ChildFilesController() {

        this.recordId = ApexPages.currentPage().getParameters().get( 'id' );

        if ( String.isNotBlank( this.recordId ) ) {

            this.sObjectName = this.recordId.getSobjectType().getDescribe().getName();

            this.nameField = getNameField( this.recordId.getSobjectType() );

            this.record = (SObject) Database.query(
                String.format(
                    'SELECT {0} FROM {1} WHERE Id = {2}',
                    new String[] { this.nameField, this.sObjectName, '\'' + this.recordId + '\'' }
                )
            );

        }

    }

    /**
     * https://salesforce.stackexchange.com/questions/149788/how-to-efficiently-determine-the-name-field-of-an-sobject-for-dynamic-query?noredirect=1&lq=1
     */
    private String getNameField( SObjectType sObjectType ) {

        String nameField = 'Name';

        Map<String, SObjectField> fields = sObjectType.getDescribe().fields.getMap();

        // edge case, some special standard objects don't use 'Name' as their naming field, like Case.CaseNumber
        if ( !fields.containsKey( nameField ) || !fields.get( nameField ).getDescribe().isNameField() ) {
            for ( SObjectField field : fields.values() ) {
                DescribeFieldResult fieldDesc = field.getDescribe();
                if ( fieldDesc.isNameField() ) {
                    nameField = fieldDesc.getName();
                    break;
                }
            }
        }

        return nameField;
    }

    // ---------------------------------------------

    /**
     * Returns the columns to display in the data table.
     * Designed for lightning:datatable component.
     * https://developer.salesforce.com/docs/atlas.en-us.lightning.meta/lightning/aura_compref_lightning_datatable.htm
     */
    @AuraEnabled
    public static List<Map<String, String>> getRelatedFilesColumns() {

        List<Map<String, String>> columns = getRelatedFilesColumnsByFieldSet( 'Related_Files_Columns' );

        if ( columns.isEmpty() ) {
            columns.addAll( getDefaultRelatedFilesColumns() );
        }

        System.debug( 'relatedFilesColumns: ' + JSON.serializePretty( columns ) );

        return columns;
    }

    private static List<Map<String, String>> getRelatedFilesColumnsByFieldSet( String fieldSetName ) {

        List<Map<String, String>> columns = new List<Map<String, String>>();

        Map<String, FieldSet> fsMap = SObjectType.ContentVersion.fieldSets.getMap();

        for ( String fsName : fsMap.keySet() ) {

            FieldSet fs = fsMap.get( fsName );

            if ( fs.getName().equalsIgnoreCase( fieldSetName ) ) {

                for ( FieldSetMember fsm : fs.getFields() ) {

                    columns.add( new Map<String, String>{
                        'label' => fsm.getLabel(),
                        'fieldName' => fsm.getFieldPath().remove( '.' ),
                        'fieldPath' => fsm.getFieldPath(),
                        'type' => String.valueOf( fsm.getType() ).toUpperCase()
                    });

                }

                break;
            }

        }

        return columns;
    }

    private static List<Map<String, String>> getDefaultRelatedFilesColumns() {

        List<Map<String, String>> columns = new List<Map<String, String>>();

        columns.add( new Map<String, String>{
            'label' => 'Title',
            'fieldName' => 'Title',
            'fieldPath' => 'Title',
            'type' => 'STRING'
        });

        columns.add( new Map<String, String>{
            'label' => 'Owner Name',
            'fieldName' => 'OwnerName',
            'fieldPath' => 'Owner.Name',
            'type' => 'STRING'
        });

        columns.add( new Map<String, String>{
            'label' => 'Last Modified',
            'fieldName' => 'LastModifiedDate',
            'fieldPath' => 'LastModifiedDate',
            'type' => 'DATETIME'
        });

        columns.add( new Map<String, String>{
            'label' => 'Size',
            'fieldName' => 'HumanReadableContentSize',
            'fieldPath' => 'ContentSize',
            'type' => 'INTEGER'
        });

        return columns;
    }

    // ---------------------------------------------

    /**
     * Queries ContentDocumentLinks whose LinkedEntityId is in the sub-query
     * on the given object name where the field name equals the field value.
     *
     * Example:
     *      Calling getFiles( 'Contacts', 'Contact', 'AccountId', '001f4000005YzSiAAK' )
     *      returns files shared to contacts belonging to this account.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getRelatedFiles( String relationshipName, String objectName, String fieldName, String fieldValue ) {

        List<Map<String, Object>> files = new List<Map<String, Object>>();

        Set<ID> entityIds = queryForEntityIds( relationshipName, objectName, fieldName, fieldValue );

        if ( entityIds.size() > 0 ) {

            List<Map<String, String>> relatedFilesColumns = getRelatedFilesColumns();
            Set<String> soqlSelectColumns = buildSoqlSelectClause( relatedFilesColumns );

            String query =
                ' SELECT ' +
                    String.join( new List<String>( soqlSelectColumns ), ', ' ) +
                ' FROM ' +
                    ' ContentDocumentLink ' +
                ' WHERE ' +
                    ' LinkedEntityId IN :entityIds ';

            System.debug( 'query=' + query );

            // since we can't group by system dates or some fields on content version
            // then having to use a set to identify the unique files out of all the shared links
            Set<ContentVersion> contentVersions = new Set<ContentVersion>();
            for ( ContentDocumentLink cdl : Database.query( query ) ) {
                contentVersions.add( cdl.ContentDocument.LatestPublishedVersion );
            }

            // once we have the unique files then add to a list of wrapper classes
            // that implements our custom sorting logic since any order by in soql
            // is rendered useless by having had to dedupe with a set
            List<ContentVersionWrapper> wrappers = new List<ContentVersionWrapper>();
            for ( ContentVersion cv : contentVersions ) {
                wrappers.add( new ContentVersionWrapper( cv ) );
            }
            wrappers.sort();

            // I want to send back custom data along with the sobject, but I also
            // don't want to create another helper class since we only need this structure
            // when serializing the data back to our Lightning Component, so just using a map.
            for ( ContentVersionWrapper wrapper : wrappers ) {
                Map<String, Object> fileMap = buildFileMap( wrapper.file, relatedFilesColumns );
                files.add( fileMap );
            }

        }

        return files;
    }

    private static Set<String> buildSoqlSelectClause( List<Map<String, String>> relatedFilesColumns ) {

        Set<String> soqlSelectColumns = new Set<String>();

        for ( Map<String, String> column : relatedFilesColumns ) {
            if ( column.get( 'type' ) == 'PICKLIST' ) {
                soqlSelectColumns.add( 'toLabel(ContentDocument.LatestPublishedVersion.' + column.get( 'fieldPath' ) + ')' );
            } else {
                soqlSelectColumns.add( 'ContentDocument.LatestPublishedVersion.' + column.get( 'fieldPath' ) );
            }
        }

        // also add some standard fields I always want available
        for ( String column : new String[] { 'Id', 'ContentDocumentId', 'OwnerId', 'Owner.Name', 'ContentSize', 'PathOnClient', 'FileExtension', 'FileType', 'CreatedDate', 'LastModifiedDate' } ) {
            soqlSelectColumns.add( 'ContentDocument.LatestPublishedVersion.' + column );
        }

        return soqlSelectColumns;
    }

    private static Map<String, Object> buildFileMap( ContentVersion file, List<Map<String, String>> relatedFilesColumns ) {

        Map<String, Object> fileMap = new Map<String, Object>();

        for ( Map<String, String> column : relatedFilesColumns ) {

            String fieldName = column.get( 'fieldName' );
            String fieldPath = column.get( 'fieldPath' );

            // initialize
            fileMap.put( fieldName, null );

            // column name might be field name like 'Status'
            // or might be field path like 'Owner.Alias'
            String[] fieldPaths = fieldPath.split( '\\.' );

            SObject value = file;

            // walk object path (e.g. record.Owner)
            for ( Integer i = 0; i < fieldPaths.size() - 1; i++ ) {
                if ( value == null ) break;
                value = value.getSObject( fieldPaths[i] );
            }

            if ( value != null ) {
                // finally, retrieve property value (e.g. 'Alias' field of 'Owner.Alias' path)
                fileMap.put( fieldName, value.get( fieldPaths[fieldPaths.size() - 1] ) );
            }

        }

        // regardless the fields specified by the field set
        // these fields I always want available
        fileMap.putAll( new Map<String, Object>{
            'Id' => file.Id,
            'ContentDocumentId' => file.ContentDocumentId,
            'Title' => file.Title,
            'OwnerId' => file.OwnerId,
            'OwnerName' => file.Owner.Name,
            'ContentSize' => file.ContentSize,
            'HumanReadableContentSize' => getHumanReadableByteCount( file.ContentSize ),
            'PathOnClient' => file.PathOnClient,
            'FileExtension' => file.FileExtension,
            'FileType' => file.FileType,
            'FileTypeIconName' => 'doctype:attachment',
            'CreatedDate' => file.CreatedDate,
            'LastModifiedDate' => file.LastModifiedDate
        });

        System.debug( 'fileMap: ' + JSON.serializePretty( fileMap ) );

        return fileMap;
    }

    private static Set<ID> queryForEntityIds( String relationshipName, String objectName, String fieldName, String fieldValue ) {

        System.debug( 'querying entity ids: relationshipName=' + relationshipName + ', objectName=' + objectName + ', fieldName=' + fieldName + ', fieldValue=' + fieldValue );

        // Tasks/Event/Activity are strange objects in Salesforce
        // and have very peculiar query restrictions.
        //
        // For custom lookup fields on Activity object the relationship created
        // is not queryable directly. In fact the data is kept in a special LookedUpFromActivity object.
        // Per documentation we must perform a sub-query on child relationship to get the activities.
        // https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_objects_lookedupfromactivity.htm
        //
        // Ironically, for standard lookup fields on Tasks and Events those child relationships
        // are queryable directly but do not allow sub-queries. Ay yi yi...
        //
        // To handle these scenarios the code makes different queries and retrieves
        // the record ids in memory. Not even close to ideal but best I know how to do in synchronous solution.

        Set<ID> entityIds = new Set<ID>();

        SObjectType fieldValueSObjectType = ID.valueOf( fieldValue ).getSobjectType();
        Boolean fieldIsAccount = ( Account.SObjectType == fieldValueSObjectType );
        Boolean objectIsTask = ( 'Task' == objectName );
        Boolean objectIsEvent = ( 'Event' == objectName );

        if ( 'LookedUpFromActivity' == objectName ) {

            String recordIdsQuery = String.format(
                'SELECT id, ( SELECT id FROM {0} ORDER BY ActivityDate DESC, LastModifiedDate DESC LIMIT 500 ) FROM {1} WHERE id = {2}',
                new String[] { String.escapeSingleQuotes( relationshipName ), fieldValueSObjectType.getDescribe().getName(), quote( fieldValue ) }
            );

            System.debug( 'recordIdsQuery=' + recordIdsQuery );

            for ( List<SObject> records : Database.query( recordIdsQuery ) ) {
                for ( SObject record : records ) {
                    for ( SObject activity : record.getSObjects( relationshipName ) ) {
                        entityIds.add( activity.id );
                    }
                }
            }

        } else {

            // if querying tasks/events on an account then widen our query
            // to find any related task/event that rolls up to this account
            if ( fieldIsAccount && ( objectIsTask || objectIsEvent ) ) {
                fieldName = 'AccountId';
            }

            String recordIdsQuery = String.format(
                'SELECT id FROM {0} WHERE {1} = {2} LIMIT 10000',
                new String[] { String.escapeSingleQuotes( objectName ), String.escapeSingleQuotes( fieldName ), quote( fieldvalue ) }
            );

            System.debug( 'recordIdsQuery=' + recordIdsQuery );

            for ( List<SObject> records : Database.query( recordIdsQuery ) ) {
                for ( SObject record : records ) {
                    entityIds.add( record.id );
                }
            }

        }

        return entityIds;
    }

    /**
     * http://programming.guide/java/formatting-byte-size-to-human-readable-format.html
     * https://stackoverflow.com/questions/3263892/format-file-size-as-mb-gb-etc
     */
    private static String getHumanReadableByteCount( Decimal size ) {

        if ( size <= 0 ) {
            return '0';
        }

        String[] units = new String[] { 'B', 'KB', 'MB', 'GB', 'TB', 'EB' };
        Integer digitGroups = (Integer) ( Math.log( size ) / Math.log( 1024 ) );
        Decimal value = ( size / Math.pow( 1024, digitGroups ) ).setScale( 0, RoundingMode.DOWN );
        String text = String.valueOf( value ) + units[digitGroups];

        return text;
    }

    private static String quote( String text ) {
        return ( '\'' + text + '\'' );
    }

    /**
     * Sorts files by last modified date descending.
     */
    private class ContentVersionWrapper implements Comparable {

        public ContentVersion file { get; set; }

        public ContentVersionWrapper( ContentVersion file ) {
            this.file = file;
        }

        public Integer compareTo( Object other ) {

            ContentVersionWrapper thatWrapper = (ContentVersionWrapper) other;

            ContentVersion thisFile = this.file;
            ContentVersion thatFile = thatWrapper.file;

            ID thisFileId = thisFile.id;
            ID thatFileId = thatFile.id;

            Integer value = 0;

            if ( thisFileId != thatFileId ) {

                DateTime thisLastModifiedDate = thisFile.LastModifiedDate;
                DateTime thatLastModifiedDate = thatFile.LastModifiedDate;

                Long thisFileLastModifiedTime = ( thisLastModifiedDate != null ? thisLastModifiedDate.getTime() : 0 );
                Long thatFileLastModifiedTime = ( thatLastModifiedDate != null ? thatLastModifiedDate.getTime() : 0 );

                // =======================================================================
                // WARNING:
                //      Do not downgrade the Long compare result to Integer.
                //      You will lose precision and yield an incorrect number.
                //      Therefore if the compare result is negative/positive/zero
                //      we simply return -1/+1/0 to indicate which record sorts first.
                // =======================================================================

                Long compareResult = ( thatFileLastModifiedTime - thisFileLastModifiedTime ); // sort descending

                if ( compareResult < 0 ) {
                    return -1;
                } else if ( compareResult > 0 ) {
                    return 1;
                } else {
                    return 0;
                }

            }

            return value;
        }

    }

    // -------------------------------------------------------------

    @AuraEnabled
    public static Map<String, Object> getObjectDescribe( String myObjectName ) {

        DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get( myObjectName ).getDescribe();

        Map<String, Object> describeMap = new Map<String, Object>{
            'name' => objectDescribe.getName(),
            'localName' => objectDescribe.getLocalName(),
            'label' => objectDescribe.getLabel(),
            'labelPlural' => objectDescribe.getLabelPlural(),
            'keyPrefix' => objectDescribe.getKeyPrefix(),
            'fields' => getFieldDescribeMaps( objectDescribe.fields.getMap() ),
            'childRelationships' => getChildRelationshipMaps( objectDescribe.getChildRelationships() )
        };

        return describeMap;
    }

    private static Map<String, Map<String, Object>> getChildRelationshipMaps( List<ChildRelationship> childRelationships ) {

        Set<String> fileLinkableObjectNames = new Set<String>{ 'LookedUpFromActivity' };

        for ( SObjectType objType : ContentDocumentLink.LinkedEntityId.getDescribe().getReferenceTo() ) {

            DescribeSObjectResult objectDescribe = objType.getDescribe();

            if ( objectDescribe.isAccessible() ) {
                fileLinkableObjectNames.add( objectDescribe.getName() );
            }

        }

        Map<String, Map<String, Object>> describeMaps = new Map<String, Map<String, Object>>();

        for ( ChildRelationship relationship : childRelationships ) {

            DescribeSObjectResult objectDescribe = relationship.getChildSObject().getDescribe();
            DescribeFieldResult fieldDescribe = relationship.getField().getDescribe();

            if ( String.isNotBlank( relationship.getRelationshipName() ) && fileLinkableObjectNames.contains( objectDescribe.getName() ) ) {

                // unfortunately, apex describe info cannot get the relationship's user-friendly label
                // we only have the API name or the plural name of the object, but not what the related list is labeled
                // https://salesforce.stackexchange.com/questions/9140/access-the-related-list-label-for-a-lookup-relationship
                describeMaps.put( relationship.getRelationshipName().toUpperCase(), new Map<String, Object>{
                    'relationshipName' => relationship.getRelationshipName(),
                    'fieldName' => fieldDescribe.getName(),
                    'fieldLabel' => fieldDescribe.getLabel(),
                    'objectName' => objectDescribe.getName(),
                    'objectLabel' => objectDescribe.getLabel(),
                    'objectLabelPlural' => objectDescribe.getLabelPlural()
                });

            }

        }

        return describeMaps;
    }

    private static Map<String, Map<String, Object>> getFieldDescribeMaps( Map<String, SObjectField> fieldsMap ) {

        Map<String, Map<String, Object>> describeMaps = new Map<String, Map<String, Object>>();

        for ( String fieldName : fieldsMap.keySet() ) {

            DescribeFieldResult fieldDescribe = fieldsMap.get( fieldName ).getDescribe();

            // using local name to stay namespace agnostic wherever this code runs
            describeMaps.put( fieldDescribe.getLocalName(), new Map<String, Object>{
                'name' => fieldDescribe.getName(),
                'localName' => fieldDescribe.getLocalName(),
                'label' => fieldDescribe.getLabel(),
                'helpText' => fieldDescribe.getInlineHelpText(),
                'picklistValues' => getPicklistValuesMaps( fieldDescribe.getPicklistValues() )
            });

        }

        return describeMaps;
    }

    private static List<Map<String, Object>> getPicklistValuesMaps( List<PicklistEntry> picklistEntries ) {

        List<Map<String, Object>> options = new List<Map<String, Object>>();

        for ( PicklistEntry pke : picklistEntries ) {
            if ( pke.isActive() ) {
                options.add( new Map<String, Object>{
                    'label' => pke.getLabel(),
                    'value' => pke.getValue()
                });
            }
        }

        return options;
    }

}
/*
BSD 3-Clause License

Copyright (c) 2018, Doug Ayers
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