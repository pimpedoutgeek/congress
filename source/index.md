# Sunlight Congress API

A live JSON API for the people and work of Congress.

## Features

Lots of features and data for members of Congress:

* Look up legislators by location or by zip code.
* Official Twitter, YouTube, and Facebook accounts.
* Committees and subcommittees in Congress, including memberships and rankings.

We also provide Congress' daily work:

* All introduced bills in the House and Senate, and what occurs to them (updated daily).
* Full text search over bills, with powerful Lucene-based query syntax.
* Real time notice of votes, floor activity, and committee hearings, and when bills are scheduled for debate.

All data is served in JSON, and requires a Sunlight API key. An API key is [free to register](http://services.sunlightlabs.com/accounts/register/) and has no usage limits.

We have an [API mailing list](https://groups.google.com/forum/?fromgroups#!forum/sunlightlabs-api-discuss), and can be found on Twitter at [@sunlightlabs](http://twitter.com/sunlightlabs). Bugs and feature requests can be made on [Github Issues](https://github.com/sunlightlabs/congress/issues).


## Methods

The Sunlight Congress API lives at:

```text
http://congress.api.sunlightfoundation.com
```

<table>
<tr>
<td>[/legislators](/legislators)</td>
<td>Current legislators' names, IDs, biography, and social media.</td>
</tr><tr>
<td>[/legislators/locate](/legislators#locate)</td><td>Find representatives and senators for a `latitude`/`longitude` or `zip`.</td>
</tr><tr>
<td>/districts/locate</td><td>Find Congressional Districts for a `latitude`/`longitude` or `zip`.</td>
</tr><tr>
<td>/committees</td>
<td>Current Congressional committees, subcommittees, and their membership.</td>
</tr><tr>
<td>/bills</td>
<td>Legislation in the House and Senate, back to 2009. Updated daily.</td>
</tr><tr>
<td>/bills/search</td><td>Same as `/bills`, but allow full text search.</td>
</tr><tr>
<td>/votes</td>
<td>Roll call votes in Congress, back to 2009. Updated within minutes of votes.</td>
</tr><tr>
<td>/floor_updates</td>
<td>To-the-minute updates from the floor of the House and Senate.</td>
</tr><tr>
<td>/hearings</td>
<td>Committee hearings in Congress. Updated as hearings are announced.</td>
</tr><tr>
<td>/upcoming_bills</td>
<td>Bills scheduled for debate in the future, as announced by party leadership.</td>
</tr><tr>
<td>/videos</td>
<td>Video of the House and Senate floor, back to 2009. Updated daily.</td>
</tr><tr>
<td>/clips/search</td><td>Captions of words from House and Senate video.</td>
</tr>
</table>

## Parameters

### Filtering

You can filter on many fields with a simple key/value pair:

```text
/legislators?last_name=Smith
```

```text
/bills?bill_type=hr&congress=112
```

The API will automatically treat numbers as numbers, and "true" and "false" as booleans. Dates and times are compared as strings.

To force the API to treat a value as a string, use quotes:

```text
/legislators?thomas_id="136"
```

See the documentation for a specific data type to see what fields can be filtered on.

### Operators

The API supports 8 operators that can be combined with filters:

**gt** - the field is greater than this value<br/>
**gte** - the fiels is greater than or equal to this value<br/>
**lt** - the field is less than this value<br/>
**lte** - the field is less than or equal to this value<br/>
**not** - the field is not this value<br/>
**exists** - whether the field exists<br/>
**all** - the field is an array that contains all of these values (separated by "|")<br/>
**in** - the field is a string that is one of these values (separated by "|")<br/>

All operators are applied by adding two underscores ("__") after the field name. They cannot be combined.

**Senate votes that got more than 70 ayes**

```text
/votes?breakdown.total.ayes__gte=70&chamber=senate
```

**Bills that got an up or down vote in the House**

```text
/bills?history.house_passage_result__exists=true&chamber=house
```

**Bills cosponsored by both John McCain and Joe Lieberman**

```text
/bills?cosponsor_ids__all=M000303|L000304
```

**Bills sponsored by either John McCain and Joe Lieberman**

```text
/bills?sponsor_id__in=M000303|L000304
```

### Pagination

All results in the Congress API are paginated. Set `per_page` and `page` to control the page size and offset. The maximum `per_page` is 50.

```text
/floor_updates?chamber=house&per_page=50&page=3
```

At the top-level of every response are **count** and **page** fields, with pagination information.

```json
{
count: 163,
page: {
  per_page: 50,
  page: 3,
  count: 50
}
}
```

**count**<br/>
The total number of documents that match the query.

**page.per_page**<br/>
The `per_page` value used to find the response. Defaults to 20.

**page.page**<br/>
The `page` value used to find the response. Defaults to 1.

**page.count**<br/>
The number of actual documents in the response. Can be less than the given `per_page` if there are too few documents.

### Ordering

### Partial responses

## Full text search

### Query string

### Highlighting

## Other

### Explain mode

Add an `explain=true` parameter to any API request to return a JSON response with how the API interpreted the query, and database-specific explain information.

This is a convenience for debugging, not a "supported" API feature. Don't make automatic requests with explain mode turned on.

### Bulk Data

Core data for legislators, committees, and bills come from public domain [scrapers](https://github.com/unitedstates/congress) and [bulk data](https://github.com/unitedstates/congress-legislators) at [github.com/unitedstates](https://github.com/unitedstates/). 

The Congress API is not designed for bulk data downloads. Requests are limited to a maximum of 50 per page, and many fields need to be specifically requested. Please use the above resources to collect this data in bulk.

### Planned Features

* All amendments to bills introduced in the House and Senate.
* Draft legislation in the House, as posted to [docs.house.gov](http://docs.house.gov).
* Reports by GAO, CBO, and Congressional committees.

### More APIs

If the Sunlight Congress API doesn't have what you're looking for, check out other Congress APIs:

* [GovTrack Data API](http://www.govtrack.us/developers/api)
* [New York Times Congress API](http://developer.nytimes.com/docs/congress_api)

Or if you're looking for other government data:

* [FederalRegister.gov API](https://www.federalregister.gov/learn/developers) - Official (government-run) API for the activity of the executive branch of the US government. Includes proposed and final regulations, notices, executive orders, and much more.
* [Open States API](http://openstates.org/api/) - US legislative data for all 50 states.
* [Capitol Words API](http://capitolwords.org/api/) - Search speeches of members of Congress (the Congressional Record), and get all sorts of language analysis on frequently used words and phrases.
* [Influence Explorer API](http://data.influenceexplorer.com/api) - Data around federal lobbying, grants, contracts, and state and federal campaign contributions.