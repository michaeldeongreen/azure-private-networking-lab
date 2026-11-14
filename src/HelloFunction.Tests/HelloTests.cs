using HelloFunction;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Xunit;

namespace HelloFunction.Tests;

public class HelloTests
{
    [Fact]
    public void GetReturnsGreeting()
    {
        var result = new Hello().Run(new DefaultHttpContext().Request);

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Equal("Hello, world!", ok.Value);
    }

    [Fact]
    public void HelloIsAnAnonymousGetEndpoint()
    {
        var method = typeof(Hello).GetMethod(nameof(Hello.Run))!;
        var trigger = Assert.Single(method.GetParameters()[0].GetCustomAttributes(
            typeof(HttpTriggerAttribute), false).Cast<HttpTriggerAttribute>());

        Assert.Equal("hello", trigger.Route);
        Assert.Equal(AuthorizationLevel.Anonymous, trigger.AuthLevel);
        Assert.Equal(new[] { "get" }, trigger.Methods);
    }
}
