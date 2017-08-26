/*
Author: Doug Ayers
Website: https://douglascayers.com
GitHub: https://github.com/DouglasCAyers/sfdc-child-files-lightning
License: BSD 3-Clause License
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

        // Not all objects (namely Task and Event) support sub-queries
        // so we first query for the related record ids then bind them
        // into next query on ContentDocumentLink.
        String recordIdsQuery = String.format(
            'SELECT id FROM {0} WHERE {1} = {2}',
            new String[] { String.escapeSingleQuotes( objectName ), String.escapeSingleQuotes( fieldName ), quote( fieldvalue ) }
        );

        System.debug( 'query=' + recordIdsQuery );

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
                    ' ContentDocument.LatestPublishedVersion.FileType, ' +
                    ' ContentDocument.LatestPublishedVersion.CreatedDate, ' +
                    ' ContentDocument.LatestPublishedVersion.LastModifiedDate ' +
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
                    'FileType' => wrapper.file.FileType,
                    'FileTypeIconName' => 'doctype:attachment',
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

                // unfortunately, apex describe info cannot get the relationship's user-friendly label
                // we only have the API name or the plural name of the object, but not what the related list is labeled
                // https://salesforce.stackexchange.com/questions/9140/access-the-related-list-label-for-a-lookup-relationship
                describeMaps.put( relationship.getRelationshipName(), new Map<String, Object>{
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

Copyright (c) 2017, Doug Ayers
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