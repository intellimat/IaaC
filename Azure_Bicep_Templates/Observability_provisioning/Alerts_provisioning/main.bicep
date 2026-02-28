/* This template creates an alert triggered from application insights (VM related)*/

@description('Tags to apply')
param tags object = {}

@description('Name of the app insights that is connected to the alert. ')
param alertPrefix string

@description('Link alert to app insights.')
param appInsightsId string

// Alert: High error rate
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertPrefix}-high-error-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when error rate exceeds 10 failed requests in 15 minutes'
    severity: 2
    enabled: true
    scopes: [
      appInsightsId
    ]
    //Every 5 minutes
    // → Look back 15 minutes
    // → Check if failures > 10
    evaluationFrequency: 'PT5M' // Azure checks the metric every 5 minutes.
    windowSize: 'PT15M' // Azure looks at the last 15 minutes of metric data.
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedRequests'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: 10 // 10 If more than 10 failed requests within 15 minutes → fire alert
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}
