/**
 * Developed by Doug Ayers (douglascayers.com)
 */
public with sharing class CF_ChildFilesController {

    /**
     * Queries ContentDocumentLinks whose LinkedEntityId is in the sub-query
     * on the given object name where the field name equals the field value.
     *
     * Example:
     *      Calling getFiles( 'Contact', 'AccountId', '001f4000005YzSiAAK' )
     *      returns files shared to contacts belonging to this account.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getRelatedFiles( String objectName, String fieldName, String fieldValue ) {

        List<Map<String, Object>> files = new List<Map<String, Object>>();

        String recordIdsQuery = String.format(
            'SELECT id FROM {0} WHERE {1} = {2}',
            new String[] { String.escapeSingleQuotes( objectName ), String.escapeSingleQuotes( fieldName ), quote( fieldvalue ) }
        );

        Set<ID> entityIds = new Set<ID>();

        for ( SObject record : Database.query( recordIdsQuery ) ) {
            entityIds.add( record.id );
        }

        if ( entityIds.size() > 0 ) {

            String query =
                ' SELECT ' +
                    ' ContentDocument.LatestPublishedVersion.Id, ' +
                    ' ContentDocument.LatestPublishedVersion.ContentDocumentId, ' +
                    ' ContentDocument.LatestPublishedVersion.Title, ' +
                    ' ContentDocument.LatestPublishedVersion.OwnerId, ' +
                    ' ContentDocument.LatestPublishedVersion.Owner.Name, ' +
                    ' ContentDocument.LatestPublishedVersion.ContentSize, ' +
                    ' ContentDocument.LatestPublishedVersion.PathOnClient, ' +
                    ' ContentDocument.LatestPublishedVersion.FileExtension, ' +
                    ' ContentDocument.LatestPublishedVersion.CreatedDate, ' +
                    ' ContentDocument.LatestPublishedVersion.LastModifiedDate ' +
                ' FROM ' +
                    ' ContentDocumentLink ' +
                ' WHERE ' +
                    ' LinkedEntityId IN :entityIds ' +
                ' LIMIT 100 ';

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

            for ( ContentVersionWrapper wrapper : wrappers ) {
                files.add( new Map<String, Object>{
                    'Id' => wrapper.file.Id,
                    'ContentDocumentId' => wrapper.file.ContentDocumentId,
                    'Title' => wrapper.file.Title,
                    'OwnerId' => wrapper.file.OwnerId,
                    'OwnerName' => wrapper.file.Owner.Name,
                    'ContentSize' => wrapper.file.ContentSize,
                    'HumanReadableContentSize' => getHumanReadableByteCount( wrapper.file.ContentSize ),
                    'PathOnClient' => wrapper.file.PathOnClient,
                    'FileExtension' => wrapper.file.FileExtension,
                    'CreatedDate' => wrapper.file.CreatedDate,
                    'CreatedDateTimestamp' => wrapper.file.CreatedDate.getTime(),
                    'LastModifiedDate' => wrapper.file.LastModifiedDate,
                    'LastModifiedDateTimestamp' => wrapper.file.LastModifiedDate.getTime()
                });
            }

        }

        return files;
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

                value = ( thatFileLastModifiedTime - thisFileLastModifiedTime ).intValue(); // sort descending

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

        Set<String> fileLinkableObjectNames = new Set<String>();

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

                describeMaps.put( relationship.getRelationshipName(), new Map<String, Object>{
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