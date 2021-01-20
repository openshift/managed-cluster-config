# Explanations

## Burn Rates
### Explanation
Burn rates define the rate at which the SLO error budget is used.
A burn rate of 1 means the complete error budget is used after the complete rolling window.
### Details
In the basic implementation a couple of questions need to be asked:
* How fast to we need to be alerted?
* How much budget can we burn worst case until we're alerted?
* How fast do we want to recover?

The combinaiton of the first and the last question hints that we always want to be implementing at least a short
and a long window.

We want to avoid flapping alerts therefore a good time period to chose for a condition to exist
is 1h. We now combine that with the time to recover, which should in this case not exceed 5m
This means that a condition has to exist for the last 1h **and** 5m.

To answer how much budget we can burn before we're alerted we have to take the time frame into consideration.
The longer the evaluation period, the more budget we can allow to burn.
Burning 5% in 6 hours is probably not worse than burning 2% in 1h.
Therefore for hour guidelines we assume the following to be acceptable:

| Time Spent | Budget Burned |
|------------|---------------|
| 1h         | 2%            |
| 6h         | 5%            |
| 3d         | 10%           |

As you can see the longer the time frame, the slower the burn in our assumptions.

### The math to create alerts

Theory:

Rolling window / burn rate = days until budget burned

Practice:

```
30d / 1		= 30d
30d / 2		= 15d
30d / 10	= 3d
30d / 14,4	= 2,083~d
```

Multiplying the result, by 24 gets us the hours until budget burned

```
30d	* 24 = 720h
15d	* 24 = 360h
3d	* 24 = 72h
2.083d	* 24 = 50h
```

We know:
* Rolling window
* Desired budget burned
* desired time frame

Assuming 2% in 1h

2% in 1h adding up to 100%

```
100 / 2 = 50
1h * 50 = 50h
50 / 24 = 2.083~d
```

Calculating the burn rate

```
x = burn rate

30d / x	= 2,083
30 	= 2,083 * X
30 / 2,0833333333 = x
**14,4 = x**
```

Now we have the burn rate we can start creating our alert.
We care about the error rate. `requests with errors / all requests` gives us that.
For example 20 errors of 100 requests total:
`20 / 100 = 0,2` so a 20% error rate.
Adding the 5m time window in a real world metric:
`rate(metricsclient_request_send{status_code="5xx"}[5m]) / rate(metricsclient_request_send[5m])`

This rate needs to be bigger than the burn rate we allow ourselves in order to fire:
`> 14.4`

However we don't have 100% of all requests we can burn but only a subset based on our SLO.
Assuming an SLO of 90% success that leaves for an error budget of 10%
`14.4 * 0,1`

Bringing it home:

`rate(metricsclient_request_send{status_code="5xx"}[5m]) / rate(metricsclient_request_send[5m]) > 14.4 * 0,1` 

Now add the condition tht we have to have this condition for 5m AND 1h

```
rate(metricsclient_request_send{status_code="5xx"}[5m]) / rate(metricsclient_request_send[5m]) > 14.4 * 0.1
and
rate(metricsclient_request_send{status_code="5xx"}[1h]) / rate(metricsclient_request_send[1h]) > 14.4 * 0.1
```

You may notice how the results differ in the equasion, we need to compare the same on both sides;

```
100 * rate(metricsclient_request_send{status_code="5xx"}[5m]) / rate(metricsclient_request_send[5m]) > 14.4 * 0.1
and
100 * rate(metricsclient_request_send{status_code="5xx"}[1h]) / rate(metricsclient_request_send[1h]) > 14.4 * 0.1
```
