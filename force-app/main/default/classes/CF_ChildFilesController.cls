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
                    new String[] { this.nameField, this.sObjectName, quote( this.recordId ) }
                )
            );

        }

    }

    public String getOrgNamespace() {
        return CF_NamespaceUtils.NAMESPACE;
    }

    /**
     * https://salesforce.stackexchange.com/questions/149788/how-to-efficiently-determine-the-name-field-of-an-sobject-for-dynamic-query?noredirect=1&lq=1
     */
    private static String getNameField( SObjectType sObjectType ) {

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
    @AuraEnabled( cacheable = true )
    public static List<Map<String, Object>> getRelatedFilesColumns( String fieldSetName ) {

        List<Map<String, Object>> columns = getRelatedFilesColumnsByFieldSet( fieldSetName );

        if ( columns.isEmpty() ) {
            columns.addAll( getDefaultRelatedFilesColumns() );
        }

        for ( Map<String, Object> column : columns ) {

            List<String> fieldPaths = ( (String) column.get( 'fieldPath' ) ).split( '\\.' );
            List<SObjectType> objectTypesInFieldPath = getObjectTypesInFieldPath( ContentVersion.SObjectType, fieldPaths );

            if ( objectTypesInFieldPath.size() > 0 ) {

                SObjectType lastObjectTypeInFieldPath = objectTypesInFieldPath[objectTypesInFieldPath.size() - 1];

                if ( lastObjectTypeInFieldPath != null ) {

                    DescribeFieldResult fieldDesc = lastObjectTypeInFieldPath.getDescribe().fields.getMap().get( fieldPaths[fieldPaths.size() - 1] ).getDescribe();

                    // to know which columns the lightning:datatable should allow to be sorted by the user
                    column.put( 'sortable', fieldDesc.isSortable() );

                    // TODO implement sort
                    column.put( 'sortable', false );

                }

            }

        }

        return columns;
    }

    private static List<Map<String, Object>> getRelatedFilesColumnsByFieldSet( String fieldSetName ) {

        List<Map<String, Object>> columns = new List<Map<String, Object>>();

        Map<String, FieldSet> fsMap = SObjectType.ContentVersion.fieldSets.getMap();

        for ( String fsName : fsMap.keySet() ) {

            FieldSet fs = fsMap.get( fsName );

            if ( fs.getName().equalsIgnoreCase( fieldSetName ) ) {

                for ( FieldSetMember fsm : fs.getFields() ) {

                    // standard lookup field labels sometimes include the suffix " ID", but in the UI they rarely do,
                    // so to mimic what the user's are accustomed to then substring the suffix away.
                    Boolean isCustom = ( fsm.getFieldPath().endsWithIgnoreCase( '__c' ) );
                    String fieldLabel = ( isCustom ? fsm.getLabel() : fsm.getLabel().substringBeforeLast( ' ID' ) );

                    columns.add( new Map<String, Object>{
                        'label' => fieldLabel,
                        'fieldName' => fsm.getFieldPath().remove( '.' ), // Owner.Name => OwnerName
                        'fieldPath' => fsm.getFieldPath(),
                        'type' => String.valueOf( fsm.getType() ).toUpperCase()
                    });

                }

                break;
            }

        }

        return columns;
    }

    @TestVisible
    private static List<Map<String, Object>> getDefaultRelatedFilesColumns() {

        List<Map<String, Object>> columns = new List<Map<String, Object>>();

        columns.add( new Map<String, Object>{
            'label' => 'Title',
            'fieldName' => 'Title',
            'fieldPath' => 'Title',
            'type' => 'STRING'
        });

        columns.add( new Map<String, Object>{
            'label' => 'Owner',
            'fieldName' => 'OwnerId',
            'fieldPath' => 'OwnerId',
            'type' => 'REFERENCE'
        });

        columns.add( new Map<String, Object>{
            'label' => 'Last Modified',
            'fieldName' => 'LastModifiedDate',
            'fieldPath' => 'LastModifiedDate',
            'type' => 'DATETIME'
        });

        columns.add( new Map<String, Object>{
            'label' => 'Size',
            'fieldName' => 'ContentSize',
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
     * @param relationshipName
     *      API Name of the relationship between the parent object and the child object.
     *      For example, 'Contacts' for the relationship from Account down to Contact records.
     * @param objectName
     *      API Name of the child object whose files to get.
     *      For example, 'Contact'.
     * @param fieldName
     *      API Name of the lookup field on the child object that references the parent object.
     *      For example, 'AccountId' for the field on Contact object that references the parent Account object.
     * @param fieldValue
     *      The record id to filter by the `fieldName`.
     *      For example, this would be the parent account id if getting files belonging to contacts related to the account.
     * @param filesAndNotesFilter
     *      Indicates if the results should include just Files, Notes, or both.
     *      Valid values: FILES_ONLY, NOTES_ONLY, FILES_AND_NOTES.
     * @param fieldSetName
     *      (optional) Field set on the ContentVersion object that determines the fields to query and display.
     * Example:
     *      Calling getRelatedFiles( 'Contacts', 'Contact', 'AccountId', '001f4000005YzSiAAK', 'FieldSetName_or_Blank' )
     *      returns files shared to contacts belonging to the account with id '001f4000005YzSiAAK.
     */
    @AuraEnabled( cacheable = true )
    public static List<Map<String, Object>> getRelatedFiles( String relationshipName, String objectName, String fieldName, String fieldValue, String filesAndNotesFilter, String fieldSetName ) {

        List<Map<String, Object>> files = new List<Map<String, Object>>();

        Set<ID> entityIds = queryForEntityIds( relationshipName, objectName, fieldName, fieldValue );

        if ( entityIds.size() > 0 ) {

            List<Map<String, Object>> relatedFilesColumns = getRelatedFilesColumns( fieldSetName );

            relatedFilesColumns.addAll( getAdditionalFileColumnsForSoqlQuery( relatedFilesColumns ) );

            Set<String> soqlSelectColumns = buildSoqlSelectClause( relatedFilesColumns );

            String query =
                ' SELECT ' +
                    String.join( new List<String>( soqlSelectColumns ), ', ' ) +
                ' FROM ' +
                    ' ContentDocumentLink ' +
                ' WHERE ' +
                    ' LinkedEntityId IN :entityIds ';

            if ( String.isNotBlank( filesAndNotesFilter ) ) {
                switch on ( filesAndNotesFilter ) {
                    when 'FILES_ONLY' {
                        query += ' AND ContentDocument.LatestPublishedVersion.FileType != \'SNOTE\' ';
                    }
                    when 'NOTES_ONLY' {
                        query += ' AND ContentDocument.LatestPublishedVersion.FileType = \'SNOTE\' ';
                    }
                }
            }

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

    private static List<Map<String, Object>> getAdditionalFileColumnsForSoqlQuery( List<Map<String, Object>> relatedFilesColumns ) {

        List<Map<String, Object>> additionalColumns = new List<Map<String, Object>>();

        // The field set may include lookup fields, like the ContentVersion.LastModifiedById,
        // and we want to display those in the lightning:datatable as a link to that record and the link text
        // be the name of that related record, instead of displaying the ID value.
        //
        // To do that, then we iterate the original list of columns and for any that are lookup fields then
        // we add to our 'additionalColumns' list the field path to the lookup record's "name" field.
        // These additional columns don't change the columns displayed in the datatable, but rather will
        // query for data that we can then refer to when constructing the URLs to be displayed in the cells of the datatable.
        for ( Map<String, Object> column : relatedFilesColumns ) {

            String fieldType = (String) column.get( 'type' );
            String fieldPath = (String) column.get( 'fieldPath' );
            SObjectType objectType = ContentVersion.SObjectType;

            if ( fieldType == 'REFERENCE' ) {

                String fieldPathToNameField = '';

                // e.g. 'CreatedBy.Alias' => ('CreatedBy', 'Alias')
                String[] fieldPaths = fieldPath.split( '\\.' );

                // Special Case: if the last field in the path is a reference field,
                // then expand the field path to reference the id as a nested field.
                // This makes it consistent later on when determining the last sobject in the field path.
                if ( fieldPaths.size() > 0 && fieldPaths[fieldPaths.size() - 1].endsWithIgnoreCase( 'Id' ) ) {
                    String lastFieldPath = fieldPaths.remove( fieldPaths.size() - 1 );
                    fieldPaths.add( lastFieldPath.substringBeforeLast( 'Id' ) );
                    fieldPaths.add( 'Id' );
                }

                // Special Case: if the last field in the path is a reference field,
                // then expand the field path to reference the id as a nested field.
                // This makes it consistent later on when determining the last sobject in the field path.
                if ( fieldPaths.size() > 0 && fieldPaths[fieldPaths.size() - 1].endsWithIgnoreCase( '__c' ) ) {
                    String lastFieldPath = fieldPaths.remove( fieldPaths.size() - 1 );
                    fieldPaths.add( lastFieldPath.replace( '__c', '__r' ) );
                    fieldPaths.add( 'Id' );
                }

                // walk object path (e.g. Foo.Bar.Baz)
                for ( Integer i = 0; i < fieldPaths.size() - 1; i++ ) {

                    // convert relationship field name into its lookup field name
                    // e.g. 'Foo__r' => 'Foo__c' and 'Foo' => 'FooId'
                    String fieldPathFieldName = ( fieldPaths[i].endsWithIgnoreCase( '__r' ) ? fieldPaths[i].replace( '__r', '__c' ) : ( fieldPaths[i] + 'Id' ) );

                    // see if the field exists on the object
                    SObjectField fieldPathField = objectType.getDescribe().fields.getMap().get( fieldPathFieldName );

                    for ( SObjectType referenceTo : fieldPathField.getDescribe().getReferenceTo() ) {
                        objectType = referenceTo;
                    }

                    if ( i > 0 ) {
                        fieldPathToNameField += '.';
                    }
                    fieldPathToNameField += fieldPaths[i];

                }

                DescribeFieldResult nameFieldDesc = objectType.getDescribe().fields.getMap().get( getNameField( objectType ) ).getDescribe();
                // standard lookup field labels sometimes include the suffix " ID", but in the UI they rarely do,
                // so to mimic what the user's are accustomed to then substring the suffix away.
                String nameFieldLabel = ( nameFieldDesc.isCustom() ? nameFieldDesc.getLabel() : nameFieldDesc.getLabel().substringBeforeLast( ' ID' ) );
                additionalColumns.add( new Map<String, Object>{
                    'type' => 'STRING',
                    'fieldPath' => fieldPathToNameField + '.' + nameFieldDesc.getName(),
                    'fieldName' => fieldPathToNameField.remove( '.' ) + 'Name',
                    'label' => nameFieldLabel
                });

            }

        }

        return additionalColumns;
    }

    private static Set<String> buildSoqlSelectClause( List<Map<String, Object>> relatedFilesColumns ) {

        Set<String> soqlSelectColumns = new Set<String>();

        for ( Map<String, Object> column : relatedFilesColumns ) {
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

    private static Map<String, Object> buildFileMap( ContentVersion file, List<Map<String, Object>> relatedFilesColumns ) {

        Map<String, Object> fileMap = new Map<String, Object>();

        for ( Map<String, Object> column : relatedFilesColumns ) {

            String fieldName = (String) column.get( 'fieldName' );
            String fieldPath = (String) column.get( 'fieldPath' );

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
                Object fieldValue = value.get( fieldPaths[fieldPaths.size() - 1] );
                fileMap.put( fieldName, fieldValue );
                // and if the field value is a lookup to another object,
                // add an entry to the map that is a link to that record
                // so that we display lookup fields as links in the lightning:datatable
                DescribeFieldResult fieldDesc = value.getSObjectType().getDescribe().fields.getMap().get( fieldPaths[fieldPaths.size() - 1] ).getDescribe();
                if ( fieldDesc.getType() == DisplayType.REFERENCE ) {
                    fileMap.put( 'LinkTo' + fieldName, URL.getOrgDomainUrl().toExternalForm() + '/' + fieldValue );
                }
            }

        }

        // regardless the fields specified by the field set
        // these fields I always want available
        fileMap.putAll( new Map<String, Object>{
            'Id' => file.Id,
            'ContentDocumentId' => file.ContentDocumentId,
            'LinkToContentDocumentId' => URL.getOrgDomainUrl().toExternalForm() + '/' + file.ContentDocumentId,
            'LinkToContentVersionId' => URL.getOrgDomainUrl().toExternalForm() + '/' + file.Id,
            'Title' => file.Title,
            'OwnerId' => file.OwnerId,
            'LinkToOwnerId' => URL.getOrgDomainUrl().toExternalForm() + '/' + file.OwnerId,
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

        return fileMap;
    }

    private static Set<ID> queryForEntityIds( String relationshipName, String objectName, String fieldName, String fieldValue ) {

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

            for ( List<SObject> records : Database.query( recordIdsQuery ) ) {
                for ( SObject record : records ) {
                    entityIds.add( record.id );
                }
            }

        }

        return entityIds;
    }

    private static List<SObjectType> getObjectTypesInFieldPath( SObjectType startingType, List<String> fieldPaths ) {

        List<SObjectType> objectTypes = new List<SObjectType>();

        SObjectType currentType = startingType;

        for ( Integer i = 0; i < fieldPaths.size(); i++ ) {

            // convert relationship field name into its lookup field name
            // e.g. 'Foo__r' => 'Foo__c' and 'Foo' => 'FooId'
            String fieldName = fieldPaths[i];
            if ( i < fieldPaths.size() - 1 ) {
                if ( fieldName.endsWithIgnoreCase( '__r' ) ) {
                    fieldName = fieldName.replace( '__r', '__c' );
                } else {
                    fieldName += 'Id';
                }
            }

            // see if the field exists on the object
            if ( currentType != null ) {

                objectTypes.add( currentType );

                SObjectField field = currentType.getDescribe().fields.getMap().get( fieldName );

                if ( field.getDescribe().getReferenceTo().size() > 0 ) {
                    currentType = field.getDescribe().getReferenceTo().get( 0 );
                } else {
                    currentType = null;
                }

            }

        }

        return objectTypes;
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

    @AuraEnabled( cacheable = true )
    public static Map<String, Object> getObjectDescribe( String myObjectName ) {

        DescribeSObjectResult objectDescribe = ( (SObject) Type.forName( myObjectName ).newInstance() ).getSObjectType().getDescribe();

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

                // The user-friendly label for related lists are stored in different places for standard and custom fields.
                //
                // For standard fields, we can generally get away with using `String.splitByCharacterTypeCamelCase()` on the
                // DescribeSObjectResult.getChildRelationships()[i].getRelationshipName().
                // For example, the standard field Asset.AssetProvidedBy has a child relationship name of "ProvidedAssets",
                // which when split by camel case becomes "Provided Assets".
                //
                // For custom fields, that relationship name from Apex describe is akin to the API field name, and not
                // what we want to display to the user. Instead, we can get the relationship label via a Tooling API query.
                // The CustomField.Metadata field includes the relationship label.
                //
                // https://salesforce.stackexchange.com/questions/9140/access-the-related-list-label-for-a-lookup-relationship
                // https://github.com/douglascayers/sfdc-related-files-lightning/issues/1

                String standardFieldRelationshipLabel = String.join( relationship.getRelationshipName().splitByCharacterTypeCamelCase(), ' ' );
                String customFieldRelationshipLabel = null;

                // Per above comments, we make Tooling API query to get the relationship label for a custom field.
                if ( fieldDescribe.isCustom() ) {

                    // Task/Activity is a strange object. The lookup relationships are found in `LookedUpFromActivity`
                    // although the custom fields are defined on the `Activity` entity, so adjust the object name filter accordingly.
                    String objectNameFilter = ( objectDescribe.getLocalName() == 'LookedUpFromActivity' ? 'Activity' : objectDescribe.getLocalName() );

                    // On CustomField object, the field names don't include the namespace or __c suffix
                    String fieldNameFilter = fieldDescribe.getLocalName().substringBeforeLast( '__' );

                    CustomFieldMetadata metadata = queryCustomFieldMetadata( objectNameFilter, fieldNameFilter );

                    customFieldRelationshipLabel = ( ( metadata == null ) ? objectDescribe.getLabelPlural() : metadata.relationshipLabel );

                }

                describeMaps.put( relationship.getRelationshipName().toUpperCase(), new Map<String, Object>{
                    'relationshipName' => relationship.getRelationshipName(),
                    'relationshipLabel' => ( fieldDescribe.isCustom() ? customFieldRelationshipLabel : standardFieldRelationshipLabel ),
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

    // -------------------------------------------------------------

    /*
     * Apex classes to assist with JSON deserialization of CustomField tooling api query result.
     */

    @TestVisible
    private static CustomFieldMetadata queryCustomFieldMetadata( String objectName, String fieldName ) {

        CustomFieldMetadata metadata = null;

        try {

            String query = String.format(
                'SELECT DeveloperName, Metadata FROM CustomField WHERE TableEnumOrId = {0} AND DeveloperName = {1} LIMIT 1',
                new String[] { quote( objectName ), quote( fieldName ) }
            );

            // When invoked in context of a Lightning Component, the session id is not
            // enabled for API use (annoying...) so we need to obtain one. Thankfully,
            // Visualforce domain sessions are enabled for API use.
            PageReference vfPage = Page.CF_VisualforceDomainPage;
            Map<String, Object> vfPageJson = (Map<String, Object>) JSON.deserializeUntyped( ( Test.isRunningTest() ? '{ "sessionId" : "' + UserInfo.getSessionId() + '" }' : vfPage.getContent().toString().trim() ) );

            HttpRequest req = new HttpRequest();
            req.setEndpoint( String.format(
                '{0}/services/data/v45.0/tooling/query/?q={1}',
                new String[] { URL.getOrgDomainUrl().toExternalForm(), EncodingUtil.urlEncode( query, 'UTF-8' ) }
            ));
            req.setMethod( 'GET' );
            req.setCompressed( true );
            req.setTimeout( 120000 ); // two minutes
            req.setHeader( 'Accepts', 'application/json;charset=UTF-8' );
            req.setHeader( 'Authorization', 'Bearer ' + vfPageJson.get( 'sessionId' ) );

            System.debug( req );
            System.debug( req.getBody() );

            HttpResponse res = new Http().send( req );

            System.debug( res );
            System.debug( res.getBody() );

            CustomFieldResult result = (CustomFieldResult) JSON.deserialize( res.getBody(), CustomFieldResult.class );

            if ( result != null && result.records != null ) {
                for ( CustomFieldRecord record : result.records ) {
                    if ( record != null ) {
                        metadata = record.Metadata;
                    }
                }
            }

        } catch ( Exception e ) {

            System.debug( LoggingLevel.ERROR, e.getMessage() + ' : ' + e.getStackTraceString() );
            metadata = null;

        }

        return metadata;
    }

    @TestVisible
    private class CustomFieldResult {
        public List<CustomFieldRecord> records { get; set; }
    }

    @TestVisible
    private class CustomFieldRecord {
        public String DeveloperName { get; set; }
        public CustomFieldMetadata Metadata { get; set; }
    }

    @TestVisible
    private class CustomFieldMetadata {
        public String relationshipLabel { get; set; }
        public String relationshipName { get; set; }
    }

}
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