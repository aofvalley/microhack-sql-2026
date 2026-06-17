// migrate.bicep — Per-student Azure Migrate project.
// Gives each student a ready-to-use Azure Migrate project for Challenge 1
// (discover the SQL Server 2019 source and run the three Azure SQL assessments).
// The project is the umbrella resource shown in the portal under "Azure Migrate";
// the assessment tooling the student adds later attaches its own resources to it.

@description('Azure region. The Azure Migrate project metadata is stored here (same region as the rest of the student RG).')
param location string

@description('Short resource name prefix for this student, e.g. mhu01.')
param resourcePrefix string

@description('Extra resource tags, e.g. SecurityControl=Ignore, to satisfy MCAPS governance policies when testing.')
param resourceTags object = {}

var migrateProjectName = toLower('${resourcePrefix}-migrate')

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-06-01-preview' = {
  name: migrateProjectName
  location: location
  tags: resourceTags
  properties: {}
}

output migrateProjectName string = migrateProject.name
output migrateProjectId string = migrateProject.id
